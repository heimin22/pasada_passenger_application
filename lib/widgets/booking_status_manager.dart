import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../location/selectedLocation.dart';
import '../utils/heading_calculator.dart';
import 'booking_details_container.dart';
import 'driver_details_container.dart';
import 'driver_loading_container.dart';
import 'driver_plate_number_container.dart';
import 'eta_container.dart';
import 'payment_details_container.dart';
import 'skeleton.dart';
import 'vehicle_capacity_container.dart';

class BookingStatusManager extends StatefulWidget {
  final SelectedLocation? pickupLocation;
  final SelectedLocation? dropoffLocation;
  final String paymentMethod;
  final double fare;
  final VoidCallback onCancelBooking;
  final String driverName;
  final String plateNumber;
  final String vehicleModel;
  final String phoneNumber;
  final bool isDriverAssigned;
  final String bookingStatus;
  final LatLng? currentLocation;
  final LatLng? driverLocation;
  final int? bookingId;
  final String? selectedDiscount;
  final String? capturedImageUrl;
  final int? vehicleTotalCapacity;
  final int? vehicleSittingCapacity;
  final int? vehicleStandingCapacity;
  final Future<void> Function()? onRefreshCapacity;
  final Widget? boundsButton;

  const BookingStatusManager({
    super.key,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.paymentMethod,
    required this.fare,
    required this.onCancelBooking,
    required this.driverName,
    required this.plateNumber,
    required this.vehicleModel,
    required this.phoneNumber,
    required this.isDriverAssigned,
    this.bookingStatus = 'requested',
    this.currentLocation,
    this.driverLocation,
    this.bookingId,
    this.selectedDiscount,
    this.capturedImageUrl,
    String? capturedImagePath,
    this.vehicleTotalCapacity,
    this.vehicleSittingCapacity,
    this.vehicleStandingCapacity,
    this.onRefreshCapacity,
    this.boundsButton,
  });

  @override
  State<BookingStatusManager> createState() => _BookingStatusManagerState();
}

class _BookingStatusManagerState extends State<BookingStatusManager> {
  bool _showLoading = false;
  Timer? _debounceTimer;
  final Duration _debounceDuration = const Duration(seconds: 1);
  Timer? _autoRefreshTimer;
  bool _isRefreshingCapacity = false;

  /// Calculate distance between two points in meters using Haversine formula
  double _calculateDistance(LatLng from, LatLng to) {
    return HeadingCalculator.calculateDistance(from, to);
  }

  /// Show confirmation dialog before cancelling booking
  void _showCancelConfirmationDialog(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext bottomSheetContext) {
        return Container(
          decoration: BoxDecoration(
            color:
                isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF555555)
                        : const Color(0xFFCCCCCC),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Sad emoji icon
              const Text(
                '😢',
                style: TextStyle(
                  fontSize: 64,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 24),
              // Title (centered)
              Text(
                'Sure ka na, boss?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  color: isDarkMode
                      ? const Color(0xFFF5F5F5)
                      : const Color(0xFF121212),
                ),
              ),
              const SizedBox(height: 16),
              // Subtitle (centered)
              Text(
                'Sige, okay lang naman po kung cacancel mo na. Malayo pa naman ata si driver e.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'Inter',
                  color: isDarkMode
                      ? const Color(0xFFBBBBBB)
                      : const Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 32),
              // Buttons
              Row(
                children: [
                  // Cancel button (go back)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(bottomSheetContext),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(
                          color: isDarkMode
                              ? const Color(0xFF555555)
                              : const Color(0xFFCCCCCC),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Hindi na',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? const Color(0xFFF5F5F5)
                              : const Color(0xFF121212),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Confirm cancel button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(bottomSheetContext);
                        widget.onCancelBooking();
                      },
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: const Color(0xFFFF3B30),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontFamily: 'Inter'),
                      ),
                      child: const Text(
                        'Oo, cancel na',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF5F5F5),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant BookingStatusManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool currentlyNeedsLoadingIndicator =
        widget.bookingStatus == 'requested' ||
            (widget.bookingStatus == 'accepted' &&
                widget.isDriverAssigned &&
                (widget.driverName.isEmpty ||
                    widget.driverName == 'Driver' ||
                    widget.driverName == 'Not Available'));

    if (currentlyNeedsLoadingIndicator && !_showLoading) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounceDuration, () {
        if (mounted) setState(() => _showLoading = true);
      });
    } else if (!currentlyNeedsLoadingIndicator && _showLoading) {
      _debounceTimer?.cancel();
      // If mounted check is good practice before setState
      if (mounted) setState(() => _showLoading = false);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Widget _buildAcceptedStatusContent() {
    final bool driverDetailsAreValid = widget.isDriverAssigned &&
        widget.driverName.isNotEmpty &&
        widget.driverName != 'Driver' &&
        widget.driverName != 'Not Available';

    if (driverDetailsAreValid) {
      return DriverDetailsContainer(
        driverName: widget.driverName,
        plateNumber: widget.plateNumber,
        phoneNumber: widget.phoneNumber,
      );
    } else {
      // Show loading if booking is 'accepted' but driver details are not yet valid/available.
      return const DriverLoadingContainer();
    }
  }

  Widget _buildCancelledStatusContent(bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.orange,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Your booking has been cancelled',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                    color: isDarkMode
                        ? const Color(0xFFF5F5F5)
                        : const Color(0xFF121212),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    if (widget.bookingStatus == 'requested') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DriverLoadingContainer(),
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Colors.redAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: widget.onCancelBooking,
              child: const Text(
                'Cancel Booking',
                style: TextStyle(
                  color: Color(0xFFF5F5F5),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Scrollbar(
      child: SingleChildScrollView(
        child: Column(
          children: [
            if (widget.bookingStatus == 'accepted' ||
                widget.bookingStatus == 'ongoing') ...[
              // Start/maintain auto-refresh when driver assigned
              if (widget.isDriverAssigned)
                _AutoRefreshBinder(
                  enabled: widget.isDriverAssigned &&
                      widget.onRefreshCapacity != null,
                  start: () {
                    _autoRefreshTimer?.cancel();
                    _autoRefreshTimer =
                        Timer.periodic(const Duration(seconds: 10), (_) {
                      widget.onRefreshCapacity?.call();
                    });
                  },
                  stop: () {
                    _autoRefreshTimer?.cancel();
                  },
                ),
              // Show plate number above driver details
              DriverPlateNumberContainer(plateNumber: widget.plateNumber),
              _buildAcceptedStatusContent(),
              if (widget.isDriverAssigned)
                Column(
                  children: [
                    if (_isRefreshingCapacity)
                      _CapacitySkeleton()
                    else
                      VehicleCapacityContainer(
                        totalPassengers: widget.vehicleTotalCapacity,
                        sittingPassengers: widget.vehicleSittingCapacity,
                        standingPassengers: widget.vehicleStandingCapacity,
                      ),
                    if (widget.onRefreshCapacity != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (_isRefreshingCapacity) return;
                              setState(() => _isRefreshingCapacity = true);
                              try {
                                await widget.onRefreshCapacity!.call();
                              } finally {
                                if (mounted) {
                                  setState(() => _isRefreshingCapacity = false);
                                }
                              }
                            },
                            icon: const Icon(
                              Icons.refresh,
                              size: 16,
                              color: Color(0xFFF5F5F5),
                            ),
                            label: const Text(
                              'Refresh capacity',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Inter',
                                color: Color(0xFFF5F5F5),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              backgroundColor: const Color(0xFF00CC58),
                              foregroundColor: const Color(0xFFF5F5F5),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              minimumSize: const Size(0, 36),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              // Show ETA based on device location to drop-off (optimized with current location)
              if (widget.dropoffLocation != null)
                EtaContainer(
                  destination: widget.dropoffLocation!.coordinates,
                  currentLocation: widget
                      .currentLocation, // Pass current location for faster loading
                ),
              BookingDetailsContainer(
                pickupLocation: widget.pickupLocation,
                dropoffLocation: widget.dropoffLocation,
                bookingId: widget.bookingId,
                fare: widget.fare,
                selectedDiscount: widget.selectedDiscount,
                capturedImageUrl: widget.capturedImageUrl,
              ),
              PaymentDetailsContainer(
                paymentMethod: widget.paymentMethod,
                fare: widget.fare,
                onCancelBooking: widget.onCancelBooking,
                showCancelButton: false,
              ),
              // Show cancel button when status is accepted and driver is 500m+ from pickup
              if (widget.bookingStatus == 'accepted' &&
                  widget.driverLocation != null &&
                  widget.pickupLocation != null &&
                  _calculateDistance(
                        widget.driverLocation!,
                        widget.pickupLocation!.coordinates,
                      ) >=
                      500.0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8.0, horizontal: 16.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: const Color(0xFFFF3B30),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () => _showCancelConfirmationDialog(context),
                    child: const Text(
                      'Cancel Booking',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF5F5F5),
                      ),
                    ),
                  ),
                ),
            ] else if (widget.bookingStatus == 'cancelled')
              _buildCancelledStatusContent(isDarkMode),
          ],
        ),
      ),
    );
  }
}

class _AutoRefreshBinder extends StatefulWidget {
  final bool enabled;
  final VoidCallback start;
  final VoidCallback stop;
  const _AutoRefreshBinder(
      {required this.enabled, required this.start, required this.stop});

  @override
  State<_AutoRefreshBinder> createState() => _AutoRefreshBinderState();
}

class _AutoRefreshBinderState extends State<_AutoRefreshBinder> {
  @override
  void initState() {
    super.initState();
    if (widget.enabled) widget.start();
  }

  @override
  void didUpdateWidget(covariant _AutoRefreshBinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        widget.start();
      } else {
        widget.stop();
      }
    }
  }

  @override
  void dispose() {
    widget.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _CapacitySkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonLine(width: 120, height: 16),
          SizedBox(height: 16),
          Row(
            children: [
              SkeletonBlock(width: 90, height: 36),
              SizedBox(width: 8),
              SkeletonBlock(width: 100, height: 36),
              SizedBox(width: 8),
              SkeletonBlock(width: 110, height: 36),
            ],
          ),
        ],
      ),
    );
  }
}
