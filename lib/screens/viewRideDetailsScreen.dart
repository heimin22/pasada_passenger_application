import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pasada_passenger_app/screens/selectionScreen.dart';
import 'package:pasada_passenger_app/services/encryptionService.dart';
import 'package:pasada_passenger_app/utils/booking_id_utils.dart';
import 'package:pasada_passenger_app/utils/timezone_utils.dart';
import 'package:pasada_passenger_app/widgets/skeleton.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// networkUtilities not needed after removing map/polylines

class ViewRideDetailsScreen extends StatefulWidget {
  final Map<String, dynamic>? booking;
  final int? bookingId;

  const ViewRideDetailsScreen({super.key, this.booking, this.bookingId});

  @override
  State<ViewRideDetailsScreen> createState() => _ViewRideDetailsScreenState();
}

class _ViewRideDetailsScreenState extends State<ViewRideDetailsScreen> {
  bool isLoading = true;
  Map<String, dynamic> bookingDetails = {};
  final supabase = Supabase.instance.client;

  // Rating and review controller
  int _rating = 0;
  final TextEditingController _reviewController = TextEditingController();
  bool _canReview = true;

  // Map-related (pins only)
  GoogleMapController? mapController;
  Set<Marker> markers = {};
  bool isMapReady = false;
  late BitmapDescriptor pickupIcon;
  late BitmapDescriptor dropoffIcon;

  @override
  void initState() {
    super.initState();
    // Inspect database schema to understand relationships
    _inspectDatabaseSchema();
    _loadMarkerIcons();

    // Determine booking ID from either provided bookingId or booking map
    final int? bid = widget.bookingId ??
        (widget.booking?['booking_id'] is num
            ? (widget.booking!['booking_id'] as num).toInt()
            : int.tryParse(widget.booking?['booking_id']?.toString() ?? ''));
    if (bid != null) {
      // Fetch full booking details (including rating/review)
      fetchBookingDetails(bid).then((_) {
        if (mounted) _prepareMapMarkers();
      });
    } else {
      // No valid booking ID: stop loading
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchBookingDetails(int bookingId) async {
    try {
      // First, fetch basic booking details without relationships
      final response = await supabase
          .from('bookings')
          .select('*')
          .eq('booking_id', bookingId)
          .single();

      // Initialize rating/review state (calculate before setState)
      final ratingVal = response['rating'];
      final reviewVal = response['review'];
      bool passed12h = false;
      if (response['created_at'] != null) {
        try {
          passed12h = DateTime.now()
                  .difference(TimezoneUtils.parseToPhilippinesTime(
                      response['created_at'].toString()))
                  .inHours >
              12;
        } catch (_) {}
      }
      final canReview = ratingVal == null && !passed12h;

      // Batch initial state updates into a single setState
      setState(() {
        bookingDetails = response;
        isLoading = false;
        if (ratingVal != null) _rating = (ratingVal as num).toInt();
        _reviewController.text = reviewVal?.toString() ?? '';
        _canReview = canReview;
      });
      debugPrint('Fetched booking details: $bookingDetails');

      // Then fetch related data separately
      if (bookingDetails['driver_id'] != null) {
        try {
          final driverResponse = await supabase
              .from('driverTable')
              .select('full_name, driver_number, vehicle_id')
              .eq('driver_id', bookingDetails['driver_id'])
              .single();

          // Decrypt driver's name and phone number (AES-256 ENC V3)
          String decryptedDriverName = driverResponse['full_name'] ?? '';
          String decryptedDriverNumber = driverResponse['driver_number'] ?? '';
          try {
            final encryptionService = EncryptionService();
            await encryptionService.initialize();
            if (decryptedDriverName.isNotEmpty) {
              decryptedDriverName =
                  await encryptionService.decryptUserData(decryptedDriverName);
            }
            if (decryptedDriverNumber.isNotEmpty) {
              decryptedDriverNumber = await encryptionService
                  .decryptUserData(decryptedDriverNumber);
            }
          } catch (_) {}

          // Collect vehicle details if available
          String? plateNumber;
          if (driverResponse['vehicle_id'] != null) {
            try {
              final vehicleResponse = await supabase
                  .from('vehicleTable')
                  .select('plate_number')
                  .eq('vehicle_id', driverResponse['vehicle_id'])
                  .single();
              plateNumber = vehicleResponse['plate_number'];
            } catch (e) {
              debugPrint('Error fetching vehicle details: $e');
            }
          }

          // Batch driver and vehicle updates into a single setState
          setState(() {
            bookingDetails['driver_name'] = decryptedDriverName;
            bookingDetails['driver_number'] = decryptedDriverNumber;
            if (plateNumber != null) {
              bookingDetails['plate_number'] = plateNumber;
            }
          });
        } catch (e) {
          debugPrint('Error fetching driver details: $e');
        }
      }

      // Collect passenger and ID image updates for batching
      String? decryptedName;
      String? decryptedNumber;
      String? decryptedIdImagePath;
      bool hasPassengerData = false;

      // Fetch passenger details
      if (bookingDetails['id'] != null) {
        try {
          final passengerResponse = await supabase
              .from('passenger')
              .select('display_name, contact_number')
              .eq('id', bookingDetails['id'])
              .single();

          // Decrypt fields if needed
          final rawName = passengerResponse['display_name'] ?? '';
          final rawNumber = passengerResponse['contact_number'] ?? '';
          hasPassengerData = true;
          try {
            final encryptionService = EncryptionService();
            await encryptionService.initialize();
            decryptedName = rawName.isNotEmpty
                ? await encryptionService.decryptUserData(rawName)
                : '';
            decryptedNumber = rawNumber.isNotEmpty
                ? await encryptionService.decryptUserData(rawNumber)
                : '';
          } catch (_) {
            // If decryption fails, use raw values
            decryptedName = rawName;
            decryptedNumber = rawNumber;
          }
        } catch (e) {
          debugPrint('Error fetching passenger details: $e');
        }
      }

      // Decrypt ID image path if present
      if (bookingDetails.containsKey('passenger_id_image_path') &&
          bookingDetails['passenger_id_image_path'] != null) {
        try {
          final encryptionService = EncryptionService();
          await encryptionService.initialize();
          final encryptedPath =
              bookingDetails['passenger_id_image_path'].toString();
          if (encryptedPath.isNotEmpty) {
            decryptedIdImagePath =
                await encryptionService.decryptUserData(encryptedPath);
            debugPrint('ID image path decrypted for booking $bookingId');
          }
        } catch (e) {
          debugPrint(
              'Error decrypting ID image path for booking $bookingId: $e');
          // Keep the encrypted path if decryption fails
        }
      }

      // Batch passenger and ID image path updates into a single setState
      if (hasPassengerData || decryptedIdImagePath != null) {
        setState(() {
          if (hasPassengerData) {
            bookingDetails['passenger_name'] = decryptedName ?? '';
            bookingDetails['contact_number'] = decryptedNumber ?? '';
          }
          if (decryptedIdImagePath != null) {
            bookingDetails['passenger_id_image_path'] = decryptedIdImagePath;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching booking details: $e');
      setState(() => isLoading = false);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      Fluttertoast.showToast(
        msg: "Copied to clipboard",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
    });
  }

  Future<void> _contactSupport() async {
    final String emailAddress = 'contact.pasada@gmail.com';
    final String subject =
        'Support Request: Booking ${bookingDetails['booking_id'] ?? bookingDetails['id']}';

    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: emailAddress,
      queryParameters: {
        'subject': subject,
      },
    );

    // Attempt to launch the email client externally (same as settingsScreen)
    final bool launched = await launchUrl(
      emailLaunchUri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      // Show error message if email client couldn't be launched
      Fluttertoast.showToast(
        msg:
            'Could not launch email client. Please email $emailAddress directly.',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  // Prepare markers based on booking coordinates
  void _prepareMapMarkers() {
    try {
      if (bookingDetails['pickup_lat'] == null ||
          bookingDetails['pickup_lng'] == null ||
          bookingDetails['dropoff_lat'] == null ||
          bookingDetails['dropoff_lng'] == null) {
        return;
      }

      final pickup = LatLng(
        double.parse(bookingDetails['pickup_lat'].toString()),
        double.parse(bookingDetails['pickup_lng'].toString()),
      );
      final dropoff = LatLng(
        double.parse(bookingDetails['dropoff_lat'].toString()),
        double.parse(bookingDetails['dropoff_lng'].toString()),
      );

      final newMarkers = <Marker>{
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: pickupIcon,
          infoWindow: InfoWindow(
            title: 'Pickup',
            snippet: bookingDetails['pickup_address']?.toString(),
          ),
        ),
        Marker(
          markerId: const MarkerId('dropoff'),
          position: dropoff,
          icon: dropoffIcon,
          infoWindow: InfoWindow(
            title: 'Dropoff',
            snippet: bookingDetails['dropoff_address']?.toString(),
          ),
        ),
      };

      setState(() {
        markers = newMarkers;
        isMapReady = true;
      });

      // Fit bounds if map already created
      if (mapController != null) {
        _fitMapToBounds();
      }
    } catch (e) {
      debugPrint('Error preparing markers: $e');
    }
  }

  // Helper method to get the center position between pickup and dropoff
  LatLng _getCenterPosition() {
    try {
      if (bookingDetails['pickup_lat'] != null &&
          bookingDetails['pickup_lng'] != null &&
          bookingDetails['dropoff_lat'] != null &&
          bookingDetails['dropoff_lng'] != null) {
        final double pickupLat =
            double.parse(bookingDetails['pickup_lat'].toString());
        final double pickupLng =
            double.parse(bookingDetails['pickup_lng'].toString());
        final double dropoffLat =
            double.parse(bookingDetails['dropoff_lat'].toString());
        final double dropoffLng =
            double.parse(bookingDetails['dropoff_lng'].toString());

        return LatLng(
          (pickupLat + dropoffLat) / 2,
          (pickupLng + dropoffLng) / 2,
        );
      }
    } catch (_) {}
    return const LatLng(14.617494, 120.971770); // Manila default
  }

  // Fit the camera to include both pins
  void _fitMapToBounds() {
    if (mapController == null || markers.isEmpty) return;
    try {
      double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
      for (final m in markers) {
        minLat = m.position.latitude < minLat ? m.position.latitude : minLat;
        maxLat = m.position.latitude > maxLat ? m.position.latitude : maxLat;
        minLng = m.position.longitude < minLng ? m.position.longitude : minLng;
        maxLng = m.position.longitude > maxLng ? m.position.longitude : maxLng;
      }
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
      mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    } catch (e) {
      debugPrint('Error fitting bounds: $e');
    }
  }

  // Helper method to inspect database schema
  Future<void> _inspectDatabaseSchema() async {
    try {
      // Instead of calling custom functions, just log that we're checking schema
      debugPrint(
          'Database schema inspection skipped - using direct table queries');
    } catch (e) {
      debugPrint('Error inspecting database schema: $e');
    }
  }

  // Load custom marker icons for pickup & dropoff
  Future<void> _loadMarkerIcons() async {
    try {
      pickupIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/png/pin_pickup.png',
      );
      dropoffIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/png/pin_dropoff.png',
      );
    } catch (_) {
      // Fallback to default markers if custom assets fail
      pickupIcon = BitmapDescriptor.defaultMarkerWithHue(120); // green-ish
      dropoffIcon = BitmapDescriptor.defaultMarkerWithHue(0); // red
    }
  }

  @override
  void dispose() {
    mapController?.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor:
            isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
        elevation: 0,
        leadingWidth: 60, // Give more space for the back button
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: isDarkMode
                  ? const Color(0xFFF5F5F5)
                  : const Color(0xFF121212),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            'Ride Receipt',
            style: TextStyle(
              color: isDarkMode
                  ? const Color(0xFFF5F5F5)
                  : const Color(0xFF121212),
              fontWeight: FontWeight.bold,
              fontFamily: 'Inter',
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton(
              onPressed: _contactSupport,
              child: Text(
                'Contact Support',
                style: TextStyle(
                  color: isDarkMode
                      ? const Color(0xFFF5F5F5)
                      : const Color(0xFF121212),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ),
        ],
        centerTitle: false, // Align title to the left
      ),
      body: isLoading
          ? SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28.0, vertical: 16.0),
                child: Builder(builder: (context) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Driver details skeleton
                      SkeletonBlock(
                        width: double.infinity,
                        height: 130,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      const SizedBox(height: 20),
                      // Booking meta skeleton
                      SkeletonBlock(
                        width: double.infinity,
                        height: 120,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      const SizedBox(height: 20),
                      // Payment details skeleton
                      SkeletonBlock(
                        width: double.infinity,
                        height: 160,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      const SizedBox(height: 20),
                      // Trip details skeleton (map removed)
                      SkeletonBlock(
                        width: double.infinity,
                        height: 110,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      const SizedBox(height: 20),
                      // Pickup/Dropoff lines
                      ListItemSkeleton(screenWidth: screenWidth),
                      const SizedBox(height: 8),
                      ListItemSkeleton(screenWidth: screenWidth),
                      const SizedBox(height: 20),
                      // Review skeleton
                      SkeletonBlock(
                        width: double.infinity,
                        height: 140,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ],
                  );
                }),
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Driver Profile Section (Now at the top)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF1E1E1E)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.grey[700]!
                              : Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Driver Details',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDarkMode
                                  ? const Color(0xFFF5F5F5)
                                  : const Color(0xFF121212),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Driver Profile Picture (Left side)
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: isDarkMode
                                      ? Colors.grey[800]
                                      : Colors.grey[300],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.person,
                                  size: 50,
                                  color: isDarkMode
                                      ? Colors.grey[300]
                                      : Colors.grey[700],
                                ),
                              ),

                              // Driver Details (Right side)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      bookingDetails['driver_name'] ??
                                          'Driver Name',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'Inter',
                                        color: isDarkMode
                                            ? const Color(0xFFF5F5F5)
                                            : const Color(0xFF121212),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          bookingDetails['driver_number'] ??
                                              'N/A',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontFamily: 'Inter',
                                            color: isDarkMode
                                                ? Colors.grey[300]
                                                : Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      bookingDetails['plate_number'] ??
                                          'Plate Number',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontFamily: 'Inter',
                                        color: isDarkMode
                                            ? Colors.grey[300]
                                            : Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Booking ID and Date Section (Now second)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF1E1E1E)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.grey[700]!
                              : Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Booking ID
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Booking ID',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode
                                      ? const Color(0xFFF5F5F5)
                                      : const Color(0xFF121212),
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    BookingIdUtils.formatBookingId(
                                      bookingDetails['booking_id'] as int? ?? 0,
                                    ),
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isDarkMode
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18),
                                    onPressed: () => _copyToClipboard(
                                        BookingIdUtils.formatBookingId(
                                      bookingDetails['booking_id'] as int? ?? 0,
                                    )),
                                    color: isDarkMode
                                        ? Colors.grey[300]
                                        : Colors.grey[700],
                                  ),
                                  if (bookingDetails['ride_status'] != 'completed')
                                    IconButton(
                                      icon: const Icon(Icons.share_outlined,
                                          size: 18),
                                      onPressed: () {
                                        final id = bookingDetails['booking_id'];
                                        if (id != null) {
                                          final url =
                                              'https://pasadaapp.com/track/$id';
                                          SharePlus.instance.share(
                                            ShareParams(
                                              text:
                                                  'Boss, ito yung link ng booking ko: $url',
                                              subject: 'Track my Pasada booking',
                                            ),
                                          );
                                        }
                                      },
                                      color: isDarkMode
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
                                    ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 15),

                          // Booking Date
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Booking Date',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode
                                      ? const Color(0xFFF5F5F5)
                                      : const Color(0xFF121212),
                                ),
                              ),
                              Text(
                                bookingDetails['created_at'] != null
                                    ? TimezoneUtils.parseToPhilippinesTime(
                                            bookingDetails['created_at'])
                                        .toString()
                                        .substring(0, 16)
                                    : 'N/A',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  color: isDarkMode
                                      ? Colors.grey[300]
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Fare and Payment Section (Third position unchanged)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF1E1E1E)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.grey[700]!
                              : Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payment Details',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDarkMode
                                  ? const Color(0xFFF5F5F5)
                                  : const Color(0xFF121212),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Total Fare
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Fare',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Inter',
                                  color: isDarkMode
                                      ? const Color(0xFFF5F5F5)
                                      : const Color(0xFF121212),
                                ),
                              ),
                              Text(
                                '₱${(bookingDetails['fare'] is num ? bookingDetails['fare'].toDouble() : double.tryParse(bookingDetails['fare']?.toString() ?? '0') ?? 0.0).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  color: isDarkMode
                                      ? Colors.grey[300]
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 15),

                          // Seating Preference
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Seating Preference',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Inter',
                                  color: isDarkMode
                                      ? const Color(0xFFF5F5F5)
                                      : const Color(0xFF121212),
                                ),
                              ),
                              Text(
                                bookingDetails['seat_type']?.toString() ??
                                    'Any',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  color: isDarkMode
                                      ? Colors.grey[300]
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 15),

                          // Payment Method
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Payment Method',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Inter',
                                  color: isDarkMode
                                      ? const Color(0xFFF5F5F5)
                                      : const Color(0xFF121212),
                                ),
                              ),
                              Row(
                                children: [
                                  // Payment method icon
                                  _buildPaymentMethodIcon(
                                      bookingDetails['payment_method']
                                              ?.toString() ??
                                          'Cash'),
                                  const SizedBox(width: 8),
                                  Text(
                                    bookingDetails['payment_method']
                                            ?.toString() ??
                                        'Cash',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontFamily: 'Inter',
                                      color: isDarkMode
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Trip Details Section (Map removed)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF1E1E1E)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDarkMode ? 0.2 : 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.grey[700]!
                              : Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trip Details',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDarkMode
                                  ? const Color(0xFFF5F5F5)
                                  : const Color(0xFF121212),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Map container (pins only)
                          Container(
                            height: 200,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.grey[700]!
                                    : Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: !isMapReady
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.map,
                                          size: 50,
                                          color: isDarkMode
                                              ? Colors.grey[300]
                                              : Colors.grey[700],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Loading map...',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontFamily: 'Inter',
                                            color: isDarkMode
                                                ? Colors.grey[300]
                                                : Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : RepaintBoundary(
                                    child: GoogleMap(
                                      style: isDarkMode
                                          ? '''[
                                      {
                                        "elementType": "geometry",
                                        "stylers": [{"color": "#242f3e"}]
                                      },
                                      {
                                        "elementType": "labels.text.fill",
                                        "stylers": [{"color": "#746855"}]
                                      },
                                      {
                                        "elementType": "labels.text.stroke",
                                        "stylers": [{"color": "#242f3e"}]
                                      },
                                      {
                                        "featureType": "road",
                                        "elementType": "geometry",
                                        "stylers": [{"color": "#38414e"}]
                                      },
                                      {
                                        "featureType": "road",
                                        "elementType": "geometry.stroke",
                                        "stylers": [{"color": "#212a37"}]
                                      },
                                      {
                                        "featureType": "road",
                                        "elementType": "labels.text.fill",
                                        "stylers": [{"color": "#9ca5b3"}]
                                      }
                                    ]'''
                                          : '',
                                      cameraTargetBounds: CameraTargetBounds(
                                        LatLngBounds(
                                          southwest:
                                              LatLng(4.215806, 116.928055),
                                          northeast:
                                              LatLng(21.321780, 126.604363),
                                        ),
                                      ),
                                      initialCameraPosition: CameraPosition(
                                        target: _getCenterPosition(),
                                        zoom: 13,
                                      ),
                                      markers: markers,
                                      onMapCreated:
                                          (GoogleMapController controller) {
                                        mapController = controller;
                                        _fitMapToBounds();
                                      },
                                      zoomControlsEnabled: false,
                                      scrollGesturesEnabled: false,
                                      zoomGesturesEnabled: false,
                                      rotateGesturesEnabled: false,
                                      tiltGesturesEnabled: false,
                                      mapToolbarEnabled: false,
                                      myLocationEnabled: false,
                                      myLocationButtonEnabled: false,
                                      compassEnabled: false,
                                    ),
                                  ),
                          ),

                          const SizedBox(height: 20),

                          // Pickup and dropoff locations timeline (sleek card)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? const Color(0xFF151515)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.grey[800]!
                                    : Colors.grey[200]!,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF00CC58),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Container(
                                      width: 2,
                                      height: 36,
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isDarkMode
                                            ? Colors.grey[700]
                                            : Colors.grey[300],
                                      ),
                                    ),
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: isDarkMode
                                            ? const Color(0xFFF5F5F5)
                                            : const Color(0xFF121212),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        bookingDetails['pickup_address'] ??
                                            'Pickup Location',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isDarkMode
                                              ? Colors.grey[300]
                                              : Colors.grey[800],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        bookingDetails['dropoff_address'] ??
                                            'Dropoff Location',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isDarkMode
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Rating & Review Section
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? const Color(0xFF1E1E1E)
                                  : const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.grey[700]!
                                    : Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Rate Your Ride',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: isDarkMode
                                              ? const Color(0xFFF5F5F5)
                                              : const Color(0xFF121212),
                                        ),
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(5, (index) {
                                        final icon = Icon(
                                          index < _rating
                                              ? Icons.star
                                              : Icons.star_border,
                                          color: Colors.amber,
                                          size: 24,
                                        );
                                        if (_canReview) {
                                          return InkWell(
                                            onTap: () => setState(
                                                () => _rating = index + 1),
                                            child: icon,
                                          );
                                        }
                                        return icon;
                                      }),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _reviewController,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    fontFamily: 'Inter',
                                  ),
                                  enabled: _canReview,
                                  cursorColor: const Color(0xFF00CC58),
                                  minLines: 1,
                                  maxLines: 6,
                                  maxLength: 200,
                                  decoration: InputDecoration(
                                    focusColor: Color(0xFF00CC58),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xFF00CC58),
                                      ),
                                    ),
                                    labelText: 'Leave a review',
                                    labelStyle: TextStyle(
                                      color: isDarkMode
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Inter',
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (_canReview)
                                  ElevatedButton(
                                    onPressed: _submitReview,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00CC58),
                                      foregroundColor: const Color(0xFFF5F5F5),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      minimumSize: const Size.fromHeight(48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'Submit Review',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: ElevatedButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const selectionScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00CC58),
              foregroundColor: const Color(0xFFF5F5F5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Text(
              'Back to Home',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodIcon(String paymentMethod) {
    // Only Cash payment is supported
    return const Icon(
      Icons.money_rounded,
      color: Color(0xFF00CC58),
      size: 24,
    );
  }

  Future<void> _submitReview() async {
    final int bid = bookingDetails['booking_id'] ?? widget.bookingId;
    try {
      await supabase.from('bookings').update({
        'rating': _rating,
        'review': _reviewController.text,
      }).eq('booking_id', bid);
      Fluttertoast.showToast(
          msg: 'Review submitted!', toastLength: Toast.LENGTH_SHORT);
      setState(() {
        // lock out further reviews after successful submission
        _canReview = false;
      });
    } catch (e) {
      Fluttertoast.showToast(
          msg: 'Error submitting review: $e', toastLength: Toast.LENGTH_LONG);
    }
  }
}
