import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pasada_passenger_app/location/selectedLocation.dart';
import 'package:pasada_passenger_app/main.dart'; // For supabase
import 'package:pasada_passenger_app/screens/completedRideScreen.dart';
import 'package:pasada_passenger_app/screens/homeScreen.dart';
import 'package:pasada_passenger_app/screens/selectionScreen.dart';
import 'package:pasada_passenger_app/services/allowedStopsServices.dart';
import 'package:pasada_passenger_app/services/background_ride_service.dart';
import 'package:pasada_passenger_app/services/bookingService.dart';
import 'package:pasada_passenger_app/services/capacity_service.dart';
import 'package:pasada_passenger_app/services/driverAssignmentService.dart';
import 'package:pasada_passenger_app/services/driverService.dart';
import 'package:pasada_passenger_app/services/error_logging_service.dart';
import 'package:pasada_passenger_app/services/fare_service.dart';
import 'package:pasada_passenger_app/services/localDatabaseService.dart';
import 'package:pasada_passenger_app/services/map_location_service.dart';
import 'package:pasada_passenger_app/services/notificationService.dart';
import 'package:pasada_passenger_app/services/optimized_eta_service.dart';
import 'package:pasada_passenger_app/services/polyline_service.dart';
import 'package:pasada_passenger_app/services/route_service.dart';
// import removed: app_logger
import 'package:pasada_passenger_app/utils/exception_handler.dart';
import 'package:pasada_passenger_app/widgets/capacity_warning_dialog.dart';
import 'package:pasada_passenger_app/widgets/responsive_dialogs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookingManager {
  final HomeScreenPageState _state;
  bool _acceptedNotified = false;
  bool _progressNotificationStarted = false;
  double? _initialDistanceToDropoff;
  Timer? _completionTimer; // Polling for ride completion
  bool _reassignmentInProgress =
      false; // Prevent duplicate reassignments and capacity checks during reassignment
  bool _capacityDialogShown =
      false; // Prevent dialog from showing multiple times
  bool _capacityCheckInProgress = false; // Prevent concurrent capacity checks
  bool _isCompleted = false; // Flag to prevent multiple cleanup calls
  bool _completionNavScheduled = false; // Ensure navigation scheduled only once
  final CapacityService _capacityService = CapacityService();

  BookingManager(this._state);

  /// Calculates the distance in meters between two latitude/longitude points.
  double _calculateDistance(LatLng p1, LatLng p2) {
    const R = 6371000; // Earth's radius in meters
    final lat1 = p1.latitude * pi / 180;
    final lat2 = p2.latitude * pi / 180;
    final dLat = (p2.latitude - p1.latitude) * pi / 180;
    final dLon = (p2.longitude - p1.longitude) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  Future<void> loadActiveBooking() async {
    final prefs = await SharedPreferences.getInstance();
    final bookingId = prefs.getInt('activeBookingId');
    if (bookingId == null) return;

    _state.bookingService = BookingService();
    final apiBooking =
        await _state.bookingService!.getBookingDetails(bookingId);

    if (apiBooking != null) {
      final status = apiBooking['ride_status'];
      if (status == 'requested' ||
          status == 'accepted' ||
          status == 'ongoing') {
        _state.setState(() {
          _state.isBookingConfirmed = true;
          _state.bookingStatus = status;
          _state.selectedPickUpLocation = SelectedLocation(
            apiBooking['pickup_address'],
            LatLng(
              double.parse(apiBooking['pickup_lat'].toString()),
              double.parse(apiBooking['pickup_lng'].toString()),
            ),
          );
          _state.selectedDropOffLocation = SelectedLocation(
            apiBooking['dropoff_address'],
            LatLng(
              double.parse(apiBooking['dropoff_lat'].toString()),
              double.parse(apiBooking['dropoff_lng'].toString()),
            ),
          );
          _state.currentFare = double.parse(apiBooking['fare'].toString());
          _state.selectedPaymentMethod = apiBooking['payment_method'] ?? 'Cash';
          _state.activeBookingId = bookingId;
          if (apiBooking['seat_type'] != null) {
            _state.seatingPreference.value = apiBooking['seat_type'].toString();
          }
        });

        if (apiBooking['driver_id'] != null) {
          await _loadBookingAfterDriverAssignment(bookingId);
        }

        _state.bookingAnimationController.forward();
        _state.driverAssignmentService = DriverAssignmentService();
        _state.driverAssignmentService!.pollForDriverAssignment(
          bookingId,
          (_) => _loadBookingAfterDriverAssignment(bookingId),
          onError: () {},
          onStatusChange: (newStatus) async {
            if (_state.mounted && !_isCompleted) {
              // Stop all polling immediately if completed or cancelled
              if (newStatus == 'completed' || newStatus == 'cancelled') {
                _isCompleted = true;
                _completionTimer?.cancel();
                _completionTimer = null;
                _state.driverAssignmentService?.stopPolling();
                _state.bookingService?.stopLocationTracking();
                await _stopBackgroundServiceForRide();
                // Clear map state if cancelled
                if (newStatus == 'cancelled') {
                  _clearMapState();
                }
                await _handleRideCompletionNavigationAndCleanup();
                return;
              }

              if (newStatus == 'accepted' && !_acceptedNotified) {
                _acceptedNotified = true;
                NotificationService.showDriverFoundNotification();

                // Start background service for accepted rides
                await _startBackgroundServiceForRide(bookingId, newStatus);
              }
              if (newStatus == 'ongoing' && !_progressNotificationStarted) {
                _progressNotificationStarted = true;
                NotificationService.showRideProgressNotification(
                  progress: 0,
                  maxProgress: 100,
                );

                // Update background service for ongoing rides
                await _updateBackgroundServiceForRide(bookingId, newStatus);
              }

              if (!_isCompleted) {
                _state.setState(() => _state.bookingStatus = newStatus);
              }

              // Only fetch details if not completed/cancelled to prevent repeated calls
              if (!_isCompleted &&
                  (newStatus == 'accepted' ||
                      newStatus == 'ongoing' ||
                      newStatus == 'requested')) {
                _fetchAndUpdateBookingDetails(bookingId);
              } else if (newStatus == 'completed' && !_isCompleted) {
                // Handle completion navigation only once
                await _handleRideCompletionNavigationAndCleanup();
              }
            }
          },
        );
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _state.measureContainers());
        return;
      }
    }

    final localBooking =
        await LocalDatabaseService().getBookingDetails(bookingId);
    if (localBooking == null) {
      await prefs.remove('activeBookingId');
      return;
    }

    final status = localBooking.rideStatus;
    if (status == 'requested' || status == 'accepted' || status == 'ongoing') {
      _state.setState(() {
        _state.isBookingConfirmed = true;
        _state.selectedPickUpLocation = SelectedLocation(
          localBooking.pickupAddress,
          localBooking.pickupCoordinates,
        );
        _state.selectedDropOffLocation = SelectedLocation(
          localBooking.dropoffAddress,
          localBooking.dropoffCoordinates,
        );
        _state.currentFare = localBooking.fare;
        _state.activeBookingId = bookingId;
      });
      _state.bookingAnimationController.forward();
      final savedMethod = prefs.getString('selectedPaymentMethod');
      if (savedMethod != null && _state.mounted) {
        _state.setState(() => _state.selectedPaymentMethod = savedMethod);
      }
      try {
        final routeResponse = await supabase
            .from('official_routes')
            .select(
                'route_name, origin_lat, origin_lng, destination_lat, destination_lng, intermediate_coordinates, destination_name, polyline_coordinates')
            .eq('officialroute_id', localBooking.routeId)
            .single();
        final Map<String, dynamic> routeMap =
            Map<String, dynamic>.from(routeResponse as Map);
        var inter = routeMap['intermediate_coordinates'];
        if (inter is String) {
          try {
            inter = jsonDecode(inter);
          } catch (_) {}
        }
        routeMap['intermediate_coordinates'] = inter;
        routeMap['origin_coordinates'] = LatLng(
          double.parse(routeMap['origin_lat'].toString()),
          double.parse(routeMap['origin_lng'].toString()),
        );
        routeMap['destination_coordinates'] = LatLng(
          double.parse(routeMap['destination_lat'].toString()),
          double.parse(routeMap['destination_lng'].toString()),
        );
        _state.setState(() => _state.selectedRoute = routeMap);
      } catch (e) {
        ExceptionHandler.handleGenericException(
          e,
          'BookingManager._restoreRoute',
          userMessage: 'Failed to restore route',
          showToast: false,
        );
        ErrorLoggingService.logError(
          error: e.toString(),
          context: 'BookingManager._restoreRoute',
        );
      }
      MapLocationService().initialize((pos) {
        _state.mapScreenKey.currentState
            ?.updateDriverLocation(pos, _state.bookingStatus);
      });
      if (_state.selectedRoute != null) {
        final polyService = PolylineService();
        final coords = polyService.generateAlongRoute(
          _state.selectedRoute!['origin_coordinates'] as LatLng,
          _state.selectedRoute!['destination_coordinates'] as LatLng,
          _state.selectedRoute!['intermediate_coordinates'] as List<LatLng>,
        );
        _state.mapScreenKey.currentState?.animateRouteDrawing(
          const PolylineId('route'),
          coords,
          const Color(0xFFFFCE21),
          4,
        );
      }
      final user = supabase.auth.currentUser;
      if (user != null) {
        _state.bookingService = BookingService();
        _state.bookingService!.startLocationTracking(user.id);
        _state.driverAssignmentService = DriverAssignmentService();
        _state.driverAssignmentService!.pollForDriverAssignment(
          bookingId,
          (_) => _loadBookingAfterDriverAssignment(bookingId),
          onError: () {},
        );
      }
    } else {
      await prefs.remove('activeBookingId');
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _state.measureContainers());
  }

  Future<void> handleBookingConfirmation() async {
    // Reset capacity dialog flag for new booking
    _capacityDialogShown = false;
    if (_state.selectedRoute != null &&
        _state.selectedPickUpLocation != null &&
        _state.selectedDropOffLocation != null) {
      final int routeId = _state.selectedRoute!['officialroute_id'] ?? 0;
      final stopsService = StopsService();
      final pickupStop = await stopsService.findClosestStop(
        _state.selectedPickUpLocation!.coordinates,
        routeId,
      );
      final dropoffStop = await stopsService.findClosestStop(
        _state.selectedDropOffLocation!.coordinates,
        routeId,
      );
      if (pickupStop != null && dropoffStop != null) {
        if (dropoffStop.order <= pickupStop.order) {
          Fluttertoast.showToast(
            msg: 'Invalid route: drop-off must be after pick-up.',
          );
          return;
        }
      }
    }

    final user = supabase.auth.currentUser;
    if (user != null && _state.selectedRoute != null) {
      // Check rate limit before proceeding
      _state.bookingService = BookingService();
      final bookingService = _state.bookingService!;

      final canBook = await bookingService.canBookToday(user.id);
      if (!canBook) {
        final todayCount = await bookingService.getTodayBookingCount(user.id);
        final isDarkMode =
            Theme.of(_state.context).brightness == Brightness.dark;
        showDialog(
          context: _state.context,
          barrierDismissible: false,
          builder: (ctx) => ResponsiveDialog(
            title: 'Daily Booking Limit Reached',
            contentPadding: const EdgeInsets.all(24),
            content: Text(
              'You have reached your daily booking limit of 5 bookings. You have already made $todayCount booking(s) today. Please try again tomorrow.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'Inter',
                color: isDarkMode
                    ? const Color(0xFFDEDEDE)
                    : const Color(0xFF1E1E1E),
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size(150, 40),
                  backgroundColor: const Color(0xFF00CC58),
                  foregroundColor: const Color(0xFFF5F5F5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        );
        return;
      }

      _state.setState(() {
        _state.isBookingConfirmed = true;
        _state.bookingStatus = 'requested';
      });
      _state.bookingAnimationController.forward();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _state.measureContainers());

      final int routeId = _state.selectedRoute!['officialroute_id'] ?? 0;

      final passengerTypeToSend =
          _state.selectedDiscountSpecification.value.isNotEmpty &&
                  _state.selectedDiscountSpecification.value != 'None'
              ? _state.selectedDiscountSpecification.value
              : null;
      final bookingResult = await bookingService.createBooking(
        passengerId: user.id,
        routeId: routeId,
        pickupAddress: _state.selectedPickUpLocation!.address,
        pickupCoordinates: _state.selectedPickUpLocation!.coordinates,
        dropoffAddress: _state.selectedDropOffLocation!.address,
        dropoffCoordinates: _state.selectedDropOffLocation!.coordinates,
        paymentMethod: _state.selectedPaymentMethod ?? 'Cash',
        fare: _state
            .originalFare, // Send original fare to server, not discounted fare
        seatingPreference: _state.seatingPreference.value,
        passengerType: passengerTypeToSend,
        idImageUrl: _state.selectedIdImageUrl.value,
        onDriverAssigned: (details) =>
            _loadBookingAfterDriverAssignment(details.bookingId),
      );

      if (bookingResult.success) {
        final details = bookingResult.booking!; // bookingId, rideStatus, etc.

        // Persist active booking
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('activeBookingId', details.bookingId);
        _state.activeBookingId = details.bookingId;
        _state.setState(() => _state.bookingStatus = details.rideStatus);
        await _fetchAndUpdateBookingDetails(details.bookingId);

        // Start location-tracking for the passenger
        bookingService.startLocationTracking(user.id);

        // Reset driver-assigned flag
        _state.setState(() => _state.isDriverAssigned = false);

        // 4) **Now** start polling for driver assignment
        _state.driverAssignmentService = DriverAssignmentService();
        _state.driverAssignmentService!.pollForDriverAssignment(
          details.bookingId,
          (driverData) {
            _loadBookingAfterDriverAssignment(details.bookingId);
          },
          onError: () {},
          onStatusChange: (newStatus) async {
            if (_state.mounted && !_isCompleted) {
              // Stop all polling immediately if completed or cancelled
              if (newStatus == 'completed' || newStatus == 'cancelled') {
                _isCompleted = true;
                _completionTimer?.cancel();
                _completionTimer = null;
                _state.driverAssignmentService?.stopPolling();
                _state.bookingService?.stopLocationTracking();
                await _stopBackgroundServiceForRide();
                // Clear map state if cancelled
                if (newStatus == 'cancelled') {
                  _clearMapState();
                }
                await _handleRideCompletionNavigationAndCleanup();
                return;
              }

              if (newStatus == 'accepted' && !_acceptedNotified) {
                _acceptedNotified = true;
                NotificationService.showDriverFoundNotification();

                // Start background service for accepted rides
                await _startBackgroundServiceForRide(
                    details.bookingId, newStatus);
              }
              if (newStatus == 'ongoing' && !_progressNotificationStarted) {
                _progressNotificationStarted = true;
                NotificationService.showRideProgressNotification(
                  progress: 0,
                  maxProgress: 100,
                );

                // Update background service for ongoing rides
                await _updateBackgroundServiceForRide(
                    details.bookingId, newStatus);
              }

              if (!_isCompleted) {
                _state.setState(() => _state.bookingStatus = newStatus);
              }

              // Only fetch details if not completed/cancelled to prevent repeated calls
              if (!_isCompleted &&
                  (newStatus == 'accepted' ||
                      newStatus == 'ongoing' ||
                      newStatus == 'requested')) {
                _fetchAndUpdateBookingDetails(details.bookingId);
              } else if (newStatus == 'completed' && !_isCompleted) {
                // Handle completion navigation only once
                await _handleRideCompletionNavigationAndCleanup();
              }
            }
          },
          onTimeout: () {
            final isDarkMode =
                Theme.of(_state.context).brightness == Brightness.dark;
            showDialog(
              context: _state.context,
              barrierDismissible: false,
              builder: (ctx) => ResponsiveDialog(
                title: 'No Drivers Available',
                contentPadding: const EdgeInsets.all(24),
                content: Text(
                  NotificationService.getRandomNoDriverMessage(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Inter',
                    color: isDarkMode
                        ? const Color(0xFFDEDEDE)
                        : const Color(0xFF1E1E1E),
                  ),
                ),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size(150, 40),
                      backgroundColor: const Color(0xFF00CC58),
                      foregroundColor: const Color(0xFFF5F5F5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ).then((_) => handleNoDriverFound());
          },
        );
      } else {
        // Booking creation failed
        Fluttertoast.showToast(
          msg: bookingResult.errorMessage ?? 'Booking failed',
        );

        // Check if it's a 404 error (no drivers available)
        if (bookingResult.isNoDriversError) {
          // Show dialog and then handle as no driver found to preserve locations
          final isDarkMode =
              Theme.of(_state.context).brightness == Brightness.dark;
          showDialog(
            context: _state.context,
            barrierDismissible: false,
            builder: (ctx) => ResponsiveDialog(
              title: 'No Drivers Available',
              contentPadding: const EdgeInsets.all(24),
              content: Text(
                NotificationService.getRandomNoDriverMessage(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Inter',
                  color: isDarkMode
                      ? const Color(0xFFDEDEDE)
                      : const Color(0xFF1E1E1E),
                ),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size(150, 40),
                    backgroundColor: const Color(0xFF00CC58),
                    foregroundColor: const Color(0xFFF5F5F5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ).then((_) => handleNoDriverFound());
        } else {
          // Other booking failures - clear everything
          await handleBookingCancellation();
        }
      }
    } else {
      Fluttertoast.showToast(msg: 'User or route missing.');
      await handleBookingCancellation();
    }
  }

  Future<void> handleBookingCancellation() async {
    _isCompleted = true; // Set flag to prevent any further API calls
    _acceptedNotified = false;
    _progressNotificationStarted = false;
    NotificationService.cancelRideProgressNotification();
    _completionTimer?.cancel();
    _completionTimer = null;
    _state.driverAssignmentService?.stopPolling();
    _state.bookingService?.stopLocationTracking();

    final currentBookingId = _state.activeBookingId;

    // Clear map state first to remove driver markers/pins
    _clearMapState();

    // Update database to set ride_status to 'cancelled'
    if (currentBookingId != null) {
      try {
        _state.bookingService ??= BookingService();
        await _state.bookingService!
            .updateBookingStatus(currentBookingId, 'cancelled');
        debugPrint(
            '[BookingManager] Updated booking $currentBookingId status to cancelled in database');
      } catch (e) {
        debugPrint(
            '[BookingManager] Error updating booking status to cancelled: $e');
        // Continue with cleanup even if database update fails
      }
    }

    final prefs = await SharedPreferences.getInstance();
    if (currentBookingId != null) {
      await LocalDatabaseService().deleteBookingDetails(currentBookingId);
    }
    await prefs.remove('activeBookingId');
    await prefs.remove('pickup');
    await prefs.remove('dropoff');

    if (_state.mounted) {
      // First set status to cancelled so UI can react
      _state.setState(() {
        _state.bookingStatus = 'cancelled';
      });

      // Clear map state again after status update to ensure driver is removed
      _clearMapState();

      // Then clear all state
      _state.setState(() {
        _state.isBookingConfirmed = false;
        _state.isDriverAssigned = false;
        _state.activeBookingId = null;
        _state.selectedPickUpLocation = null;
        _state.selectedDropOffLocation = null;
        _state.selectedRoute = null;
        _state.bookingStatus = ''; // Reset booking status
        // Clear driver-related state
        _state.driverName = '';
        _state.plateNumber = '';
        _state.phoneNumber = '';
        _state.vehicleModel = '';
        _state.vehicleTotalCapacity = null;
        _state.vehicleSittingCapacity = null;
        _state.vehicleStandingCapacity = null;
      });
      _state.bookingAnimationController.reverse();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_state.mounted) {
          _state.measureContainers();
          // Final map clear to ensure everything is removed
          _clearMapState();
        }
      });
    }
  }

  void _updateDriverDetails(Map<String, dynamic> driverData) async {
    if (!_state.mounted) {
      return;
    }
    var driver = driverData['driver'];
    if (driver == null) {
      _state.setState(() {
        _state.isDriverAssigned = false;
      });
      return;
    }
    if (driver is List && driver.isNotEmpty) {
      driver = driver[0];
    } else if (driver is List && driver.isEmpty) {
      _state.setState(() {
        _state.isDriverAssigned = false;
      });
      return;
    }

    if (driver is! Map<String, dynamic>) {
      _state.setState(() {
        _state.isDriverAssigned = false;
      });
      return;
    }

    _state.setState(() {
      _state.driverName =
          _extractField(driver, ['full_name', 'name', 'driver_name']);
      _state.plateNumber = _extractField(
          driver, ['plate_number', 'plateNumber', 'vehicle_plate', 'plate']);
      _state.phoneNumber = _extractField(driver, [
        'driver_number',
        'phone_number',
        'phoneNumber',
        'contact_number',
        'phone'
      ]);
      _state.isDriverAssigned = (_state.driverName.isNotEmpty &&
          _state.driverName != 'Driver' &&
          _state.driverName != 'Not Available');
    });

    // Try to extract vehicle capacity details from the same payload if available
    try {
      final dynamic vehicle = driver['vehicle'] ?? driver['vehicle_details'];
      if (vehicle is Map<String, dynamic>) {
        final total = vehicle['passenger_capacity'];
        final sit = vehicle['sitting_passenger'];
        final stand = vehicle['standing_passenger'];
        _state.setState(() {
          _state.vehicleTotalCapacity =
              total == null ? null : int.tryParse(total.toString());
          _state.vehicleSittingCapacity =
              sit == null ? null : int.tryParse(sit.toString());
          _state.vehicleStandingCapacity =
              stand == null ? null : int.tryParse(stand.toString());
        });
        debugPrint(
            '[BookingManager] Updated capacity from vehicle object: total=$total, sitting=$sit, standing=$stand');
        _evaluateCapacityAndMaybeReassign();
      }

      // Also support flat fields (as returned by get_driver_details_by_booking RPC)
      if (driver.containsKey('passenger_capacity') ||
          driver.containsKey('sitting_passenger') ||
          driver.containsKey('standing_passenger')) {
        _state.setState(() {
          _state.vehicleTotalCapacity = driver['passenger_capacity'] == null
              ? _state.vehicleTotalCapacity
              : int.tryParse(driver['passenger_capacity'].toString());
          _state.vehicleSittingCapacity = driver['sitting_passenger'] == null
              ? _state.vehicleSittingCapacity
              : int.tryParse(driver['sitting_passenger'].toString());
          _state.vehicleStandingCapacity = driver['standing_passenger'] == null
              ? _state.vehicleStandingCapacity
              : int.tryParse(driver['standing_passenger'].toString());
        });

        _evaluateCapacityAndMaybeReassign();
      }
    } catch (_) {}

    // Extract driver's current_location from driver details RPC
    dynamic currentLoc = driver['current_location'];
    LatLng? driverLatLng;
    if (currentLoc != null) {
      // GeoJSON format: { type: 'Point', coordinates: [lon, lat] }
      if (currentLoc is Map && currentLoc['coordinates'] is List) {
        final coords = List.from(currentLoc['coordinates']);
        driverLatLng = LatLng(coords[1] as double, coords[0] as double);
      }
      // WKT format: 'POINT(lon lat)'
      else if (currentLoc is String) {
        final match =
            RegExp(r"POINT\(([-\d\.]+) ([-\d\.]+)\)").firstMatch(currentLoc);
        if (match != null) {
          final lon = double.parse(match.group(1)!);
          final lat = double.parse(match.group(2)!);
          driverLatLng = LatLng(lat, lon);
        }
      }
    }
    if (driverLatLng != null && !_isCompleted) {
      // Only update driver location if booking is not completed/cancelled
      if (_state.bookingStatus != 'cancelled' &&
          _state.bookingStatus != 'completed') {
        _state.mapScreenKey.currentState
            ?.updateDriverLocation(driverLatLng, _state.bookingStatus);
      }
      // Update ride progress notification
      final dropoff = _state.selectedDropOffLocation?.coordinates;
      if (dropoff != null) {
        // Do not post progress notifications after completion
        if (_isCompleted || _state.bookingStatus == 'completed') {
          // Ensure it's cancelled if any late updates come in
          NotificationService.cancelRideProgressNotification();
        } else if (_state.bookingStatus == 'accepted' ||
            _state.bookingStatus == 'ongoing') {
          _initialDistanceToDropoff ??=
              _calculateDistance(driverLatLng, dropoff);
          final currentDistance = _calculateDistance(driverLatLng, dropoff);
          final int progress =
              (((_initialDistanceToDropoff! - currentDistance) /
                          _initialDistanceToDropoff!) *
                      100)
                  .clamp(0, 100)
                  .round();
          // Compute ETA using optimized service based on booking status
          try {
            final optimizedEtaService = OptimizedETAService();
            final etaResp = await optimizedEtaService.getETA(
              origin: {
                'lat': driverLatLng.latitude,
                'lng': driverLatLng.longitude,
              },
              destination: {
                'lat': dropoff.latitude,
                'lng': dropoff.longitude,
              },
              bookingStatus: _state.bookingStatus,
              driverLocation: driverLatLng,
            );
            final int etaSec = (etaResp['eta_seconds'] as int?) ?? 0;
            final int etaMin = (etaSec / 60).ceil();
            final String etaTitle =
                etaMin > 0 ? 'Arriving at $etaMin min' : 'Arriving';
            await NotificationService.showRideProgressNotification(
              progress: progress,
              maxProgress: 100,
              title: etaTitle,
            );
          } catch (e) {
            await NotificationService.showRideProgressNotification(
              progress: progress,
              maxProgress: 100,
              title: 'Arriving',
            );
          }
        }
      }
    }

    // Start polling for completion after acceptance
    if (_state.activeBookingId != null) {
      _startCompletionPolling(_state.activeBookingId!);
    }
  }

  String _extractField(dynamic data, List<String> keys) {
    if (data is! Map) return '';
    for (var key in keys) {
      if (data.containsKey(key) && data[key] != null) {
        return data[key].toString();
      }
    }
    return '';
  }

  Future<void> _fetchAndUpdateBookingDetails(int bookingId) async {
    // Prevent API calls if already completed
    if (_isCompleted) {
      debugPrint(
          "[BookingManager] _fetchAndUpdateBookingDetails: Already completed, skipping API call for booking ID $bookingId");
      return;
    }

    _state.bookingService ??= BookingService();

    if (!_state.mounted) {
      debugPrint(
          "[BookingManager] _fetchAndUpdateBookingDetails: State not mounted for booking ID $bookingId at entry. Bailing out.");
      return;
    }
    debugPrint(
        "[BookingManager] _fetchAndUpdateBookingDetails: Fetching for booking ID $bookingId. Mounted: ${_state.mounted}");

    final details = await _state.bookingService!.getBookingDetails(bookingId);
    if (!_state.mounted) {
      // Check again after await
      debugPrint(
          "[BookingManager] _fetchAndUpdateBookingDetails: State not mounted for booking ID $bookingId after getBookingDetails. Bailing out.");
      return;
    }

    if (details != null) {
      debugPrint(
          "[BookingManager] _fetchAndUpdateBookingDetails: Details for booking ID $bookingId: $details");
      if (details['ride_status'] == 'completed' && !_isCompleted) {
        debugPrint(
            "[BookingManager] _fetchAndUpdateBookingDetails: Ride COMPLETED for booking ID $bookingId. Navigating.");
        _isCompleted = true;
        await _handleRideCompletionNavigationAndCleanup();
        return;
      }
      _state.setState(() {
        // Always trust the database status - it's the source of truth
        final serverStatus = details['ride_status'] ?? 'requested';
        final serverDriverId = details['driver_id'];

        // Simply use the server status - database is always correct
        _state.bookingStatus = serverStatus;

        debugPrint(
            '[BookingManager] Updated status from database: $serverStatus (driver_id: $serverDriverId)');

        // If no driver_id, clear driver assignment state
        if (serverDriverId == null) {
          _state.isDriverAssigned = false;
        }

        // If driver is assigned and status is accepted/ongoing, clear reassignment flags
        if (serverDriverId != null &&
            (serverStatus == 'accepted' || serverStatus == 'ongoing')) {
          if (_reassignmentInProgress) {
            debugPrint(
                '[BookingManager] Driver found during reassignment, clearing reassignment flag');
            _reassignmentInProgress = false;
            _capacityDialogShown = false;
          }
        }
        if (details['fare'] != null) {
          // Get the original fare from server
          final originalFare =
              double.tryParse(details['fare'].toString()) ?? _state.currentFare;

          // Preserve discount calculation on client side
          if (_state.selectedDiscountSpecification.value.isNotEmpty &&
              _state.selectedDiscountSpecification.value != 'None') {
            // Recalculate discounted fare to ensure discount is preserved (holiday-aware)
            FareService.calculateDiscountedFareWithHoliday(
                    originalFare, _state.selectedDiscountSpecification.value)
                .then((value) {
              if (_state.mounted) {
                _state.setState(() {
                  _state.currentFare = value;
                });
              }
            });
            // Update original fare for UI display
            _state.originalFare = originalFare;
          } else {
            // No discount, use fare from server
            _state.currentFare = originalFare;
          }
        }
        if (details['payment_method'] != null) {
          _state.selectedPaymentMethod = details['payment_method'];
        }
        // Update seating preference if provided
        if (details['seat_type'] != null) {
          _state.seatingPreference.value = details['seat_type'].toString();
        }
      });

      // CRITICAL: Always load driver details if driver_id is present
      // This ensures UI updates even during reassignment when driver is found
      if (details['driver_id'] != null) {
        // If driver was just assigned (was null, now present), clear reassignment flag
        if (_reassignmentInProgress) {
          debugPrint(
              '[BookingManager] Driver found during reassignment polling, clearing reassignment flag');
          _reassignmentInProgress = false;
          _capacityDialogShown = false;
        }

        // Load driver details immediately - this will update isDriverAssigned and driver info
        // This is critical during reassignment to ensure UI updates when new driver is found
        await _loadBookingAfterDriverAssignment(bookingId);

        // Ensure status is at least 'accepted' if driver is assigned
        if (_state.mounted &&
            _state.bookingStatus == 'requested' &&
            _state.isDriverAssigned) {
          _state.setState(() {
            _state.bookingStatus = 'accepted';
          });
        }
      } else {
        debugPrint(
            "[BookingManager] _fetchAndUpdateBookingDetails: No driver_id found for booking $bookingId.");
        // Only clear driver assignment state if no driver AND we're not in reassignment
        // During reassignment, we might have temporary null driver_id while server updates
        if (_state.mounted && !_reassignmentInProgress) {
          _state.setState(() {
            _state.isDriverAssigned = false;
          });
        }
      }
    }
  }

  Future<void> _loadBookingAfterDriverAssignment(int bookingId) async {
    // Prevent loading if booking is already completed/cancelled
    if (_isCompleted) {
      debugPrint(
          "[BookingManager] _loadBookingAfterDriverAssignment: Booking already completed/cancelled, skipping driver load for $bookingId");
      return;
    }

    // First, check if booking has a driver_id
    try {
      final bookingDetails =
          await _state.bookingService?.getBookingDetails(bookingId);
      if (bookingDetails == null || bookingDetails['driver_id'] == null) {
        debugPrint(
            "[BookingManager] No driver_id in booking $bookingId yet, skipping driver load");
        return;
      }
      // Check if booking is cancelled
      if (bookingDetails['ride_status'] == 'cancelled') {
        debugPrint(
            "[BookingManager] Booking $bookingId is cancelled, skipping driver load");
        _isCompleted = true;
        return;
      }
    } catch (e) {
      debugPrint("[BookingManager] Error checking booking for driver_id: $e");
      // If error occurs, check if we should continue
      if (_isCompleted) return;
    }

    // Try fetching full driver details (including current_location) via RPC
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        final result =
            await supabase.rpc('get_driver_details_by_booking', params: {
          'p_booking_id': bookingId,
          'p_user_id': user.id,
        }).single() as Map<String, dynamic>?;
        if (result != null) {
          _updateDriverDetails({'driver': result});
          // If vehicle info is not provided by RPC, fetch via DB join
          if (_state.vehicleTotalCapacity == null &&
              _state.vehicleSittingCapacity == null &&
              _state.vehicleStandingCapacity == null) {
            await _fetchVehicleCapacityForBooking(bookingId);
          }

          // Check capacity after driver assignment
          _evaluateCapacityAndMaybeReassign();
          return;
        }
      } catch (e) {
        debugPrint(
            "[BookingManager] Error fetching driver details via RPC: $e");
        // Continue to fallback methods
      }
    }

    // Fallback: Try direct DB fetch (most reliable when RPC fails)
    try {
      await _fetchDriverDetailsDirectlyFromDB(bookingId);
      // If successful, we're done
      if (_state.isDriverAssigned) {
        // Check capacity after driver assignment
        _evaluateCapacityAndMaybeReassign();
        return;
      }
    } catch (e) {
      debugPrint(
          "[BookingManager] Error fetching driver details directly from DB: $e");
    }

    // Last resort: Try driver service methods if direct DB fetch failed
    try {
      final bookingData =
          await _state.driverAssignmentService?.fetchBookingDetails(bookingId);
      if (bookingData != null) {
        debugPrint(
            "[BookingManager] _loadBookingAfterDriverAssignment: Fetched bookingData for $bookingId: $bookingData");
        final driverId = bookingData['driver_id'];
        if (driverId != null) {
          debugPrint(
              "[BookingManager] _loadBookingAfterDriverAssignment: driver_id $driverId found. Fetching driver details via getDriverDetailsByBooking.");

          // Try getDriverDetailsByBooking first
          final driverDetails =
              await DriverService().getDriverDetailsByBooking(bookingId);
          if (driverDetails != null) {
            debugPrint(
                "[BookingManager] _loadBookingAfterDriverAssignment: Got driverDetails via getDriverDetailsByBooking for $bookingId: $driverDetails. Calling _updateDriverDetails.");
            _updateDriverDetails(driverDetails);
            if (_state.vehicleTotalCapacity == null &&
                _state.vehicleSittingCapacity == null &&
                _state.vehicleStandingCapacity == null) {
              await _fetchVehicleCapacityForBooking(bookingId);
            }
            _evaluateCapacityAndMaybeReassign();
            return;
          }

          // Try getDriverDetails as fallback
          debugPrint(
              "[BookingManager] _loadBookingAfterDriverAssignment: getDriverDetailsByBooking returned null. Trying getDriverDetails with driverId $driverId.");
          final directDetails =
              await DriverService().getDriverDetails(driverId.toString());
          if (directDetails != null) {
            debugPrint(
                "[BookingManager] _loadBookingAfterDriverAssignment: Got directDetails for driver $driverId: $directDetails. Calling _updateDriverDetails.");
            _updateDriverDetails(directDetails);
            if (_state.vehicleTotalCapacity == null &&
                _state.vehicleSittingCapacity == null &&
                _state.vehicleStandingCapacity == null) {
              await _fetchVehicleCapacityForBooking(bookingId);
            }
            _evaluateCapacityAndMaybeReassign();
            return;
          }
        }
      }
    } catch (e) {
      debugPrint("[BookingManager] Error in fallback driver details fetch: $e");
    }

    // If all methods fail, at least ensure we mark driver as assigned if driver_id exists
    // This prevents the UI from stuck in "Looking for driver" state
    try {
      final bookingDetails =
          await _state.bookingService?.getBookingDetails(bookingId);
      if (bookingDetails != null && bookingDetails['driver_id'] != null) {
        debugPrint(
            "[BookingManager] Driver_id exists but couldn't fetch details. Setting basic driver state to update UI.");
        if (_state.mounted) {
          _state.setState(() {
            _state.isDriverAssigned = true;
            // Set minimal driver info to indicate driver is assigned
            _state.driverName = 'Driver';
            _state.plateNumber = '';
          });
        }
        // Try to fetch capacity and driver details in background
        _fetchVehicleCapacityForBooking(bookingId);
        _fetchDriverDetailsDirectlyFromDB(bookingId);
      }
    } catch (e) {
      debugPrint("[BookingManager] Error in final fallback: $e");
    }

    // Check capacity after driver assignment
    _evaluateCapacityAndMaybeReassign();
  }

  Future<void> _fetchDriverDetailsDirectlyFromDB(int bookingId) async {
    // Prevent fetching if booking is already completed/cancelled
    if (_isCompleted) {
      debugPrint(
          "[BookingManager] _fetchDriverDetailsDirectlyFromDB: Booking already completed/cancelled, skipping driver fetch for $bookingId");
      return;
    }

    try {
      final booking = await supabase
          .from('bookings')
          .select('driver_id, ride_status')
          .eq('booking_id', bookingId)
          .single();

      // Check if booking is cancelled
      if (booking['ride_status'] == 'cancelled') {
        debugPrint(
            "[BookingManager] _fetchDriverDetailsDirectlyFromDB: Booking $bookingId is cancelled, skipping driver fetch");
        _isCompleted = true;
        return;
      }

      if (!booking.containsKey('driver_id') || booking['driver_id'] == null) {
        return;
      }

      // Double-check _isCompleted after async call
      if (_isCompleted) {
        debugPrint(
            "[BookingManager] _fetchDriverDetailsDirectlyFromDB: Booking marked as completed during fetch, aborting");
        return;
      }
      final driverId = booking['driver_id'];
      final driver = await supabase
          .from('driverTable')
          .select('driver_id, full_name, driver_number, vehicle_id')
          .eq('driver_id', driverId)
          .single();
      String plate = 'Unknown';
      if (driver.containsKey('vehicle_id') && driver['vehicle_id'] != null) {
        final vehicle = await supabase
            .from('vehicleTable')
            .select(
                'plate_number, passenger_capacity, sitting_passenger, standing_passenger')
            .eq('vehicle_id', driver['vehicle_id'])
            .single();
        if (vehicle.containsKey('plate_number')) {
          plate = vehicle['plate_number'];
        }
        _state.setState(() {
          _state.vehicleTotalCapacity = vehicle['passenger_capacity'] == null
              ? null
              : int.tryParse(vehicle['passenger_capacity'].toString());
          _state.vehicleSittingCapacity = vehicle['sitting_passenger'] == null
              ? null
              : int.tryParse(vehicle['sitting_passenger'].toString());
          _state.vehicleStandingCapacity = vehicle['standing_passenger'] == null
              ? null
              : int.tryParse(vehicle['standing_passenger'].toString());
        });
      }
      _state.setState(() {
        _state.driverName = driver['full_name'] ?? 'Driver';
        _state.phoneNumber = driver['driver_number'] ?? '';
        _state.plateNumber = plate;
        _state.isDriverAssigned = true;
      });
      // Start polling for completion when using direct DB fetch as well
      if (_state.activeBookingId != null) {
        debugPrint(
            "[BookingManager] _fetchDriverDetailsDirectlyFromDB: Driver details restored. Starting completion polling for booking ID $bookingId.");
        _startCompletionPolling(bookingId);
      }
    } catch (e) {
      ExceptionHandler.handleDatabaseException(
        e,
        'BookingManager._fetchDriverDetailsDirectlyFromDB',
        userMessage: 'Failed to fetch driver details',
        showToast: false,
      );
      ErrorLoggingService.logError(
        error: e.toString(),
        context: 'BookingManager._fetchDriverDetailsDirectlyFromDB',
      );
    }
  }

  Future<void> _fetchVehicleCapacityForBooking(int bookingId) async {
    try {
      final booking = await supabase
          .from('bookings')
          .select('driver_id')
          .eq('booking_id', bookingId)
          .single();
      if (!booking.containsKey('driver_id')) return;
      final driverId = booking['driver_id'];
      final driver = await supabase
          .from('driverTable')
          .select('vehicle_id')
          .eq('driver_id', driverId)
          .single();
      if (!driver.containsKey('vehicle_id') || driver['vehicle_id'] == null) {
        return;
      }
      final vehicle = await supabase
          .from('vehicleTable')
          .select('passenger_capacity, sitting_passenger, standing_passenger')
          .eq('vehicle_id', driver['vehicle_id'])
          .single();
      _state.setState(() {
        _state.vehicleTotalCapacity = vehicle['passenger_capacity'] == null
            ? null
            : int.tryParse(vehicle['passenger_capacity'].toString());
        _state.vehicleSittingCapacity = vehicle['sitting_passenger'] == null
            ? null
            : int.tryParse(vehicle['sitting_passenger'].toString());
        _state.vehicleStandingCapacity = vehicle['standing_passenger'] == null
            ? null
            : int.tryParse(vehicle['standing_passenger'].toString());
      });
      debugPrint(
          '[BookingManager] Updated capacity from DB fallback: total=${vehicle['passenger_capacity']}, sitting=${vehicle['sitting_passenger']}, standing=${vehicle['standing_passenger']}');
      _evaluateCapacityAndMaybeReassign();
    } catch (e) {
      ExceptionHandler.handleDatabaseException(
        e,
        'BookingManager._fetchVehicleCapacityForBooking',
        userMessage: 'Failed to fetch vehicle capacity',
        showToast: false,
      );
      ErrorLoggingService.logError(
        error: e.toString(),
        context: 'BookingManager._fetchVehicleCapacityForBooking',
      );
    }
  }

  /// Poll the booking status every 10 seconds until it's completed
  void _startCompletionPolling(int bookingId) {
    if (_completionTimer != null || _isCompleted) {
      return; // Already polling or completed
    }
    debugPrint(
        "[BookingManager] _startCompletionPolling: Starting for booking ID $bookingId");
    _completionTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) async {
      // Stop polling if already completed
      if (_isCompleted) {
        timer.cancel();
        _completionTimer = null;
        return;
      }

      // quiet frequent polling log
      try {
        final details =
            await _state.bookingService?.getBookingDetails(bookingId);
        if (details != null) {
          // quiet payload log
          final status = details['ride_status'];

          // Stop polling if cancelled
          if (status == 'cancelled' && !_isCompleted) {
            _isCompleted = true;
            timer.cancel();
            _completionTimer = null;
            _state.driverAssignmentService?.stopPolling();
            _state.bookingService?.stopLocationTracking();
            debugPrint(
                '[BookingManager] _startCompletionPolling: Booking $bookingId is cancelled, stopping polling');
            return;
          }

          // If ride ongoing, update driver location & polyline
          if (status == 'ongoing' && !_isCompleted) {
            final driverDetails =
                await DriverService().getDriverDetailsByBooking(bookingId);
            if (driverDetails != null) {
              _updateDriverDetails(driverDetails);
            }
          }
          // When completed, navigate and cleanup
          if (status == 'completed' && !_isCompleted) {
            _isCompleted = true;
            timer.cancel(); // Stop this specific timer instance.
            _completionTimer = null;
            // Stop all other polling services
            _state.driverAssignmentService?.stopPolling();
            _state.bookingService?.stopLocationTracking();
            await _handleRideCompletionNavigationAndCleanup();
          }
        } else {
          debugPrint(
              "[BookingManager] Polling for booking ID $bookingId returned null details.");
        }
      } catch (e) {
        debugPrint(
            '[BookingManager] Error polling for completion for booking ID $bookingId: $e');
      }
    });
  }

  Future<void> _handleRideCompletionNavigationAndCleanup() async {
    // Prevent multiple navigation schedules
    if (_completionNavScheduled) {
      debugPrint(
          "[BookingManager] _handleRideCompletionNavigationAndCleanup: Navigation already scheduled, skipping");
      return;
    }

    _isCompleted = true;
    _acceptedNotified = false;
    _progressNotificationStarted = false;
    NotificationService.cancelRideProgressNotification();
    // Stop background running as soon as completion is detected
    await _stopBackgroundServiceForRide();
    if (!_state.mounted) return;

    final BuildContext safeContext = _state.context;
    final int? completedBookingId = _state.activeBookingId;

    // Stop all polling immediately
    _completionTimer?.cancel();
    _completionTimer = null;
    _state.driverAssignmentService?.stopPolling();
    _state.bookingService?.stopLocationTracking();

    if (completedBookingId != null) {
      await LocalDatabaseService().deleteBookingDetails(completedBookingId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('activeBookingId');
    await prefs.remove('pickup');
    await prefs.remove('dropoff');

    // Only update state, don't navigate immediately
    // Navigation will happen in post-frame callback
    if (_state.mounted) {
      _state.setState(() {
        // Keep activeBookingId temporarily for navigation, clear after
        _state.isBookingConfirmed = false;
        _state.isDriverAssigned = false;
        _state.bookingStatus = 'completed';
      });
    }

    _completionNavScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (safeContext.mounted && completedBookingId != null) {
        // Use the root navigator to avoid nested navigator/bottom sheet interference
        final rootNavigator = Navigator.of(safeContext, rootNavigator: true);
        try {
          // First, close any modals/bottom sheets/dialogs
          rootNavigator.popUntil((route) => route is PageRoute);
        } catch (e) {
          throw Exception(e);
        }
        try {
          // Then, pop to the root of the app's main stack
          rootNavigator.popUntil((route) => route.isFirst);
        } catch (e) {
          throw Exception(e);
        }

        // Slightly defer replacement to let pops settle and avoid route animation races
        Future.delayed(const Duration(milliseconds: 50), () {
          if (!safeContext.mounted) return;
          rootNavigator
              .pushReplacement(
            MaterialPageRoute(
              settings: const RouteSettings(name: '/completed'),
              builder: (_) => CompletedRideScreen(
                arrivedTime: DateTime.now(),
                bookingId: completedBookingId,
              ),
            ),
          )
              .then((_) {
            // Clear activeBookingId after navigation completes (when user leaves completed screen)
            if (_state.mounted) {
              _state.setState(() {
                _state.activeBookingId = null;
              });
            }
          });
        });
      } else if (safeContext.mounted) {
        // Fallback: Navigate to selection screen with bottom nav bar if booking ID is no longer available
        Navigator.of(safeContext, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const selectionScreen(),
          ),
          (route) => false,
        );
      }
    });
  }

  // Public method to refresh driver details and vehicle capacity for a booking
  Future<void> refreshDriverAndCapacity(int bookingId) async {
    // Prevent refresh if booking is already completed/cancelled
    if (_isCompleted) {
      debugPrint(
          '[BookingManager] refreshDriverAndCapacity: Booking already completed/cancelled, skipping refresh for $bookingId');
      return;
    }

    try {
      debugPrint(
          '[BookingManager] refreshDriverAndCapacity: Starting refresh for booking $bookingId');

      // First, fetch fresh booking details
      await _fetchAndUpdateBookingDetails(bookingId);

      // Check again after async call
      if (_isCompleted) {
        debugPrint(
            '[BookingManager] refreshDriverAndCapacity: Booking marked as completed during refresh, aborting');
        return;
      }

      // Then fetch fresh driver and vehicle details
      await _loadBookingAfterDriverAssignment(bookingId);

      // Force a state update to ensure UI rebuilds
      if (_state.mounted) {
        _state.setState(() {
          _state.capacityRefreshTick += 1; // force rebuild of capacity subtree
        });
      }

      _evaluateCapacityAndMaybeReassign();

      debugPrint(
          '[BookingManager] refreshDriverAndCapacity: Completed refresh for booking $bookingId');
    } catch (e) {
      debugPrint('[BookingManager] refreshDriverAndCapacity error: $e');
    }
  }

  /// Public method to manually trigger capacity check (for testing)
  Future<void> checkCapacityManually(int bookingId) async {
    debugPrint(
        '[BookingManager] Manual capacity check triggered for booking $bookingId');
    await _checkCapacityAndShowDialog(bookingId);
  }

  void _evaluateCapacityAndMaybeReassign() {
    // Don't check capacity if reassignment is in progress
    if (_reassignmentInProgress) {
      debugPrint(
          '[BookingManager] Skipping capacity check - reassignment in progress');
      return;
    }
    if (_state.activeBookingId == null) return;

    // Call the async method without awaiting to avoid blocking
    _checkCapacityAndShowDialog(_state.activeBookingId!);
  }

  /// Checks capacity using actual database data and shows dialog if needed
  Future<void> _checkCapacityAndShowDialog(int bookingId) async {
    // Prevent concurrent capacity checks
    if (_capacityCheckInProgress) {
      debugPrint(
          '[BookingManager] Capacity check already in progress, skipping...');
      return;
    }

    _capacityCheckInProgress = true;
    try {
      // If dialog is already shown, skip check entirely
      if (_capacityDialogShown) {
        debugPrint(
            '[BookingManager] Dialog already shown, skipping capacity check');
        return;
      }

      // Get actual vehicle capacity from database
      final capacityData =
          await _capacityService.getVehicleCapacityForBooking(bookingId);
      if (capacityData == null) {
        debugPrint('[BookingManager] Could not fetch vehicle capacity data');
        return;
      }

      final int sitting = capacityData['sitting_passenger'] ?? 0;
      final int standing = capacityData['standing_passenger'] ?? 0;
      final String seatType = _state.seatingPreference.value;

      const int sittingLimit = 27; // Updated limit as per requirements
      const int standingLimit = 3;

      bool exceeded = false;
      String alternativeSeatType = '';

      if (seatType == 'Sitting') {
        exceeded = sitting >= sittingLimit;
        alternativeSeatType = 'Standing';
      } else if (seatType == 'Standing') {
        exceeded = standing >= standingLimit;
        alternativeSeatType = 'Sitting';
      } else {
        // Any: exceeded only if both are full
        exceeded = (sitting >= sittingLimit) && (standing >= standingLimit);
        alternativeSeatType =
            'Standing'; // Default to standing for 'Any' preference
      }

      debugPrint(
          '[BookingManager] Capacity check - Sitting: $sitting/$sittingLimit, Standing: $standing/$standingLimit, SeatType: $seatType, Exceeded: $exceeded');

      if (exceeded) {
        // Check flag before showing dialog to prevent duplicate dialogs
        if (!_capacityDialogShown) {
          debugPrint('[BookingManager] Capacity exceeded! Showing dialog...');
          // Set flag IMMEDIATELY to prevent race condition from concurrent checks
          _capacityDialogShown = true;
          try {
            await _showCapacityWarningDialog(
                bookingId, seatType, alternativeSeatType);
          } catch (e) {
            // If dialog fails to show, reset flag
            _capacityDialogShown = false;
            debugPrint('[BookingManager] Error showing capacity dialog: $e');
          }
        } else {
          debugPrint(
              '[BookingManager] Capacity exceeded but dialog already shown, skipping...');
        }
      } else {
        debugPrint('[BookingManager] Capacity within limits, no dialog needed');
        _capacityDialogShown =
            false; // Reset flag when capacity is within limits
      }
    } catch (e) {
      debugPrint('[BookingManager] Error checking capacity: $e');
      // Reset flag on error so check can be retried
      _capacityDialogShown = false;
    } finally {
      _capacityCheckInProgress = false;
    }
  }

  /// Shows the capacity warning dialog to the user
  Future<void> _showCapacityWarningDialog(
      int bookingId, String currentSeatType, String alternativeSeatType) async {
    if (_reassignmentInProgress) {
      debugPrint('[BookingManager] Reassignment in progress, skipping dialog');
      _capacityDialogShown = false; // Reset flag if skipping
      return;
    }

    // Note: Flag should already be set by caller to prevent race conditions
    // We don't check it here because it was set synchronously before this async call

    // Check if booking is in a state where capacity changes are allowed
    final canChange =
        await _capacityService.canChangeSeatingPreference(bookingId);
    if (!canChange) {
      debugPrint(
          '[BookingManager] Cannot show capacity dialog - booking not in assigned/accepted status');
      // For testing purposes, let's show the dialog anyway if capacity is exceeded
      // This will help verify the dialog is working correctly
      debugPrint(
          '[BookingManager] Testing mode: Showing dialog anyway for testing');
    }

    if (!_state.mounted) {
      _capacityDialogShown = false; // Reset flag if not mounted
      return;
    }

    await showDialog(
      context: _state.context,
      barrierDismissible: false,
      builder: (context) => CapacityWarningDialog(
        currentSeatType: currentSeatType,
        alternativeSeatType: alternativeSeatType,
        onAccept: () async {
          Navigator.of(context).pop();
          await _handleCapacityChangeAccept(bookingId, alternativeSeatType);
        },
        onDecline: () async {
          Navigator.of(context).pop();
          await _handleCapacityChangeDecline(bookingId);
        },
      ),
    );
  }

  /// Handles when user accepts the capacity change
  Future<void> _handleCapacityChangeAccept(
      int bookingId, String newSeatType) async {
    try {
      debugPrint(
          '[BookingManager] User accepted capacity change to $newSeatType');

      // Reset the dialog flag since user made a decision
      _capacityDialogShown = false;

      // Update seating preference in database
      final success = await _capacityService.updateSeatingPreference(
        bookingId: bookingId,
        newSeatType: newSeatType,
      );

      if (success) {
        // Update local state
        _state.setState(() {
          _state.seatingPreference.value = newSeatType;
        });

        Fluttertoast.showToast(
          msg: 'Seating preference updated to $newSeatType',
          toastLength: Toast.LENGTH_SHORT,
        );

        // Refresh capacity data
        await refreshDriverAndCapacity(bookingId);
      } else {
        Fluttertoast.showToast(
          msg: 'Failed to update seating preference. Please try again.',
          toastLength: Toast.LENGTH_LONG,
        );
      }
    } catch (e) {
      debugPrint('[BookingManager] Error handling capacity change accept: $e');
      Fluttertoast.showToast(
        msg: 'An error occurred. Please try again.',
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  /// Handles when user declines the capacity change
  Future<void> _handleCapacityChangeDecline(int bookingId) async {
    // Prevent duplicate calls
    if (_reassignmentInProgress) {
      debugPrint(
          '[BookingManager] Reassignment already in progress, ignoring duplicate decline');
      return;
    }

    _reassignmentInProgress = true;
    try {
      debugPrint(
          '[BookingManager] User declined capacity change, resetting booking for reassignment');

      // Keep dialog flag true to prevent showing again during reassignment
      // Will be reset when reassignment completes or a new driver is assigned

      // Capture current driver to avoid reassigning the same driver
      String? previousDriverId;
      try {
        final details =
            await _state.bookingService?.getBookingDetails(bookingId);
        if (details != null && details['driver_id'] != null) {
          previousDriverId = details['driver_id'].toString();
        }
      } catch (_) {}

      // Preserve booking details before resetting (route, locations, fare, seating preference)
      final retainedRoute = _state.selectedRoute;
      final retainedPickUp = _state.selectedPickUpLocation;
      final retainedDropOff = _state.selectedDropOffLocation;
      final retainedFare = _state.currentFare;
      final retainedOriginalFare = _state.originalFare;
      final retainedSeating = _state.seatingPreference.value;
      final retainedPaymentMethod = _state.selectedPaymentMethod;
      final retainedDiscountSpec = _state.selectedDiscountSpecification.value;
      final retainedIdImageUrl = _state.selectedIdImageUrl.value;

      // Reset booking to 'requested' status for driver reassignment
      // Always use resetBookingForReassignment, not cancel, since we're reassigning
      final success =
          await _capacityService.resetBookingForReassignment(bookingId);

      if (success) {
        // Reset driver-related state only (preserves booking details)
        _resetBookingState();
        // Ensure background service is stopped before reassignment
        await _stopBackgroundServiceForRide();

        // Reset notification flags for new driver assignment after reassignment
        _acceptedNotified = false;
        _progressNotificationStarted = false;

        // Always reset to 'requested' for reassignment
        const newStatus = 'requested';

        // Restore booking details and update local state to reflect the status change
        _state.setState(() {
          // Preserve route and locations
          _state.selectedRoute = retainedRoute;
          _state.selectedPickUpLocation = retainedPickUp;
          _state.selectedDropOffLocation = retainedDropOff;
          _state.currentFare = retainedFare;
          _state.originalFare = retainedOriginalFare;
          _state.seatingPreference.value = retainedSeating;
          _state.selectedPaymentMethod = retainedPaymentMethod;
          _state.selectedDiscountSpecification.value = retainedDiscountSpec;
          _state.selectedIdImageUrl.value = retainedIdImageUrl;

          // CRITICAL: Set status to requested/cancelled immediately after reset
          // This ensures local state matches server state (no driver assigned)
          _state.bookingStatus = newStatus;
          _state.isDriverAssigned = false;
        });

        // Update local DB status to match (will delete if requested)
        await _state.bookingService?.updateBookingStatus(bookingId, newStatus);

        // Persist preserved values to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (retainedPickUp != null) {
          await prefs.setString('pickup', jsonEncode(retainedPickUp.toJson()));
        }
        if (retainedDropOff != null) {
          await prefs.setString(
              'dropoff', jsonEncode(retainedDropOff.toJson()));
        }
        if (retainedRoute != null) {
          await RouteService.saveRoute(retainedRoute);
        }

        Fluttertoast.showToast(
          msg: 'Looking for another driver...',
          toastLength: Toast.LENGTH_SHORT,
        );

        // Request a new driver assignment for the reset booking
        _state.bookingService ??= BookingService();
        try {
          debugPrint(
              '[BookingManager] Requesting new driver assignment for booking $bookingId');

          // Get booking details to pass to assignDriver
          final bookingDetails =
              await _state.bookingService!.getBookingDetails(bookingId);
          if (bookingDetails != null && retainedRoute != null) {
            final returnedBookingId = await _state.bookingService!.assignDriver(
              bookingId,
              fare: retainedFare,
              paymentMethod: retainedPaymentMethod ?? 'Cash',
              excludeDriverId: previousDriverId,
              seatType: retainedSeating,
            );

            // Check if backend created a new booking with a new ID
            if (returnedBookingId != bookingId) {
              debugPrint(
                  '[BookingManager] New booking created during reassignment: $returnedBookingId (old: $bookingId)');

              // Update active booking ID to the new booking
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('activeBookingId', returnedBookingId);

              if (_state.mounted) {
                _state.setState(() {
                  _state.activeBookingId = returnedBookingId;
                });
              }

              // Use the new booking ID for polling
              bookingId = returnedBookingId;

              debugPrint(
                  '[BookingManager] Updated activeBookingId to $returnedBookingId for reassignment');
            } else {
              debugPrint(
                  '[BookingManager] Driver assignment requested successfully for booking $bookingId');
            }
          } else {
            debugPrint(
                '[BookingManager] Could not fetch booking details for driver assignment');
          }
        } catch (e) {
          debugPrint('[BookingManager] Error requesting driver assignment: $e');
          // Continue anyway - polling might still work
          // Reset reassignment flag on error so it can be retried
          _reassignmentInProgress = false;
        }

        // Start polling for new driver assignment
        _state.driverAssignmentService = DriverAssignmentService();
        _state.driverAssignmentService!.pollForDriverAssignment(
          bookingId,
          (driverData) async {
            // Driver has been assigned - load details immediately
            debugPrint(
                '[BookingManager] Driver assigned callback triggered for booking $bookingId');
            // Reset reassignment flag immediately when driver is found
            _reassignmentInProgress = false;
            _capacityDialogShown = false;

            // Update status to accepted immediately
            if (_state.mounted) {
              _state.setState(() {
                _state.bookingStatus = 'accepted';
              });
            }

            // Load driver details to update UI immediately
            await _loadBookingAfterDriverAssignment(bookingId);

            // Show notification that driver was found
            if (!_acceptedNotified) {
              _acceptedNotified = true;
              NotificationService.showDriverFoundNotification();
            }

            // Start background service for accepted rides
            await _startBackgroundServiceForRide(bookingId, 'accepted');
          },
          onError: () {},
          onStatusChange: (newStatus) async {
            if (_state.mounted && !_isCompleted) {
              // Stop all polling immediately if completed or cancelled
              if (newStatus == 'completed' || newStatus == 'cancelled') {
                _isCompleted = true;
                _completionTimer?.cancel();
                _completionTimer = null;
                _state.driverAssignmentService?.stopPolling();
                _state.bookingService?.stopLocationTracking();
                await _stopBackgroundServiceForRide();
                // Clear map state if cancelled
                if (newStatus == 'cancelled') {
                  _clearMapState();
                }
                await _handleRideCompletionNavigationAndCleanup();
                return;
              }

              // Update status immediately
              if (!_isCompleted) {
                if (!_isCompleted) {
                  _state.setState(() => _state.bookingStatus = newStatus);
                }
              }

              if (newStatus == 'accepted') {
                // Reset notification flag for new driver assignment
                if (!_acceptedNotified) {
                  _acceptedNotified = true;
                  NotificationService.showDriverFoundNotification();
                }

                // Reset reassignment flag and capacity dialog flag when new driver is assigned
                _reassignmentInProgress = false;
                _capacityDialogShown = false;

                // CRITICAL: Load driver details first, then fetch booking details
                // Wait for driver loading to complete before fetching booking details
                await _loadBookingAfterDriverAssignment(bookingId);

                // Start background service for accepted rides
                await _startBackgroundServiceForRide(bookingId, newStatus);

                // Fetch and update booking details after driver is loaded to ensure sync
                // This will also trigger another driver load check, but _loadBookingAfterDriverAssignment
                // handles duplicate calls gracefully
                if (!_isCompleted) {
                  await _fetchAndUpdateBookingDetails(bookingId);
                }
              } else if (newStatus == 'ongoing' && !_isCompleted) {
                if (!_progressNotificationStarted) {
                  _progressNotificationStarted = true;
                  NotificationService.showRideProgressNotification(
                    progress: 0,
                    maxProgress: 100,
                  );
                }

                // Update background service for ongoing rides
                await _updateBackgroundServiceForRide(bookingId, newStatus);

                // Fetch and update booking details
                await _fetchAndUpdateBookingDetails(bookingId);
              } else if (newStatus == 'completed' && !_isCompleted) {
                // Handle completion navigation only once
                await _handleRideCompletionNavigationAndCleanup();
              }
            }
          },
        );
      } else {
        Fluttertoast.showToast(
          msg: 'Failed to reset booking. Please try again.',
          toastLength: Toast.LENGTH_LONG,
        );
        // Reset flag on failure
        _reassignmentInProgress = false;
        _capacityDialogShown = false;
      }
    } catch (e) {
      debugPrint('[BookingManager] Error handling capacity change decline: $e');
      Fluttertoast.showToast(
        msg: 'An error occurred. Please try again.',
        toastLength: Toast.LENGTH_LONG,
      );
      // Reset flag on error
      _reassignmentInProgress = false;
      _capacityDialogShown = false;
    }
  }

  /// Resets all booking-related state when reassigning driver
  void _resetBookingState() {
    debugPrint(
        '[BookingManager] Resetting all booking state for driver reassignment');

    // Reset driver-related state
    _state.driverName = '';
    _state.plateNumber = '';
    _state.vehicleModel = '';
    _state.phoneNumber = '';

    // Reset vehicle capacity state
    _state.vehicleTotalCapacity = null;
    _state.vehicleSittingCapacity = null;
    _state.vehicleStandingCapacity = null;
    _state.capacityRefreshTick = 0;

    // Reset driver assignment service
    if (_state.driverAssignmentService != null) {
      _state.driverAssignmentService!.stopPolling();
      _state.driverAssignmentService = null;
    }

    // Reset completion timer
    if (_completionTimer != null) {
      _completionTimer!.cancel();
      _completionTimer = null;
    }

    // Reset progress tracking
    _progressNotificationStarted = false;
    _acceptedNotified = false;

    // Reset capacity dialog flag
    _capacityDialogShown = false;

    // Clear map polylines and markers
    _clearMapState();

    debugPrint('[BookingManager] All booking state reset successfully');
  }

  /// Clears all map-related state (polylines, markers, driver location)
  void _clearMapState() {
    debugPrint('[BookingManager] Clearing map state');

    // Clear all map overlays and reset state
    if (_state.mapScreenKey.currentState != null) {
      _state.mapScreenKey.currentState!.clearAll();
    }
  }

  /// Handles cancellation when no drivers found, retaining route, locations, seating preference, and fare
  void handleNoDriverFound() {
    // Preserve current selections
    final retainedRoute = _state.selectedRoute;
    final retainedPickUp = _state.selectedPickUpLocation;
    final retainedDropOff = _state.selectedDropOffLocation;
    final retainedFare = _state.currentFare;
    final retainedSeating = _state.seatingPreference.value;
    _acceptedNotified = false;
    _progressNotificationStarted = false;
    NotificationService.cancelRideProgressNotification();
    _completionTimer?.cancel();
    _completionTimer = null;
    _state.driverAssignmentService?.stopPolling();
    _state.bookingService?.stopLocationTracking();

    final currentBookingId = _state.activeBookingId;

    SharedPreferences.getInstance().then((prefs) async {
      if (currentBookingId != null) {
        await LocalDatabaseService().deleteBookingDetails(currentBookingId);
      }
      await prefs.remove('activeBookingId');

      // Save retained locations to SharedPreferences to ensure they persist
      if (retainedPickUp != null) {
        await prefs.setString('pickup', jsonEncode(retainedPickUp.toJson()));
      }
      if (retainedDropOff != null) {
        await prefs.setString('dropoff', jsonEncode(retainedDropOff.toJson()));
      }
      // Save retained route to ensure it persists
      if (retainedRoute != null) {
        await RouteService.saveRoute(retainedRoute);
      }
    });

    if (_state.mounted) {
      _state.setState(() {
        _state.isBookingConfirmed = false;
        _state.isDriverAssigned = false;
        _state.activeBookingId = null;
        _state.bookingStatus = '';
        // Restore retained values
        _state.selectedRoute = retainedRoute;
        _state.selectedPickUpLocation = retainedPickUp;
        _state.selectedDropOffLocation = retainedDropOff;
        _state.currentFare = retainedFare;
        _state.seatingPreference.value = retainedSeating;
      });
      _state.bookingAnimationController.reverse();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_state.mounted) {
          _state.measureContainers();
        }
      });
    }
  }

  /// Start background service for ride tracking
  Future<void> _startBackgroundServiceForRide(
      int bookingId, String rideStatus) async {
    try {
      if (_state.selectedPickUpLocation != null &&
          _state.selectedDropOffLocation != null) {
        await BackgroundRideService.startService(
          bookingId: bookingId,
          rideStatus: rideStatus,
          pickupAddress: _state.selectedPickUpLocation!.address,
          dropoffAddress: _state.selectedDropOffLocation!.address,
        );
        debugPrint(
            'Background service started for booking $bookingId with status $rideStatus');
      }
    } catch (e) {
      debugPrint('Error starting background service: $e');
    }
  }

  /// Update background service for ride status changes
  Future<void> _updateBackgroundServiceForRide(
      int bookingId, String rideStatus) async {
    try {
      await BackgroundRideService.updateServiceNotification(
        rideStatus: rideStatus,
        driverName: _state.driverName.isNotEmpty ? _state.driverName : null,
        estimatedArrival: null, // Not available in current implementation
        dropoffAddress: _state.selectedDropOffLocation?.address,
      );
      debugPrint(
          'Background service updated for booking $bookingId with status $rideStatus');
    } catch (e) {
      debugPrint('Error updating background service: $e');
    }
  }

  /// Stop background service when ride ends
  Future<void> _stopBackgroundServiceForRide() async {
    try {
      await BackgroundRideService.stopService();
      debugPrint('Background service stopped');
    } catch (e) {
      debugPrint('Error stopping background service: $e');
    }
  }
}
