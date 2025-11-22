import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pasada_passenger_app/location/selectedLocation.dart';
import 'package:pasada_passenger_app/managers/booking_manager.dart';
import 'package:pasada_passenger_app/widgets/booking_status_manager.dart';

/// Booking bottom sheet wrapper for the home screen
class HomeBookingSheet extends StatelessWidget {
  final DraggableScrollableController controller;
  final String bookingStatus;
  final SelectedLocation? pickupLocation;
  final SelectedLocation? dropoffLocation;
  final String paymentMethod;
  final double fare;
  final BookingManager bookingManager;
  final String driverName;
  final String plateNumber;
  final String vehicleModel;
  final String phoneNumber;
  final bool isDriverAssigned;
  final LatLng? currentLocation;
  final LatLng? driverLocation;
  final int? bookingId;
  final String? selectedDiscount;
  final String? capturedImagePath;
  final String? capturedImageUrl;
  final int? vehicleTotalCapacity;
  final int? vehicleSittingCapacity;
  final int? vehicleStandingCapacity;
  final Future<void> Function()? onRefreshCapacity;
  // an external tick that changes on capacity updates to force rebuild of subtree
  final int? capacityRefreshTick;
  // Optional in-sheet bounds button
  final Widget? boundsButton;

  const HomeBookingSheet({
    super.key,
    required this.controller,
    required this.bookingStatus,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.paymentMethod,
    required this.fare,
    required this.bookingManager,
    required this.driverName,
    required this.plateNumber,
    required this.vehicleModel,
    required this.phoneNumber,
    required this.isDriverAssigned,
    required this.currentLocation,
    this.driverLocation,
    this.bookingId,
    this.selectedDiscount,
    this.capturedImagePath,
    this.capturedImageUrl,
    this.vehicleTotalCapacity,
    this.vehicleSittingCapacity,
    this.vehicleStandingCapacity,
    this.onRefreshCapacity,
    this.capacityRefreshTick,
    this.boundsButton,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: controller,
      // Shrink sheet to fit content when still in 'requested' status
      initialChildSize: bookingStatus == 'requested' ? 0.25 : 0.4,
      minChildSize: bookingStatus == 'requested' ? 0.25 : 0.2,
      maxChildSize: 0.8,
      builder: (context, scrollController) {
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      // key includes capacity tick to ensure rebuilds when it changes
                      child: BookingStatusManager(
                        key: ValueKey<String>(
                            '${bookingStatus}_${capacityRefreshTick ?? 0}'),
                        pickupLocation: pickupLocation,
                        dropoffLocation: dropoffLocation,
                        paymentMethod: paymentMethod,
                        fare: fare,
                        onCancelBooking:
                            bookingManager.handleBookingCancellation,
                        driverName: driverName,
                        plateNumber: plateNumber,
                        vehicleModel: vehicleModel,
                        phoneNumber: phoneNumber,
                        isDriverAssigned: isDriverAssigned,
                        bookingStatus: bookingStatus,
                        currentLocation: currentLocation,
                        driverLocation: driverLocation,
                        bookingId: bookingId,
                        selectedDiscount: selectedDiscount,
                        capturedImagePath: capturedImagePath,
                        capturedImageUrl: capturedImageUrl,
                        vehicleTotalCapacity: vehicleTotalCapacity,
                        vehicleSittingCapacity: vehicleSittingCapacity,
                        vehicleStandingCapacity: vehicleStandingCapacity,
                        onRefreshCapacity: onRefreshCapacity,
                        boundsButton: boundsButton,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (boundsButton != null)
              Positioned(
                right: 16,
                bottom: 16,
                child: boundsButton!,
              ),
          ],
        );
      },
    );
  }
}
