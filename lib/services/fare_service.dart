import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pasada_passenger_app/utils/map_utils.dart';

/// Service to calculate fare based on distance in kilometers
class FareService {
  static const double baseFare = 15.0;
  static const double ratePerKm = 2.2;
  static const double discountPercentage = 0.20; // 20% discount

  /// Calculates fare for the given distance (in km)
  static double calculateFare(double distanceInKm) {
    if (distanceInKm <= 4.0) {
      return baseFare;
    }
    return baseFare + (distanceInKm - 4.0) * ratePerKm;
  }

  /// Calculates discounted fare based on passenger type
  static double calculateDiscountedFare(
      double originalFare, String passengerType) {
    if (passengerType.isEmpty || passengerType == 'None') {
      return originalFare;
    }

    // Apply 20% discount for Student, Senior Citizen, and PWD
    return originalFare * (1 - discountPercentage);
  }

  /// Calculates discounted fare (holiday rule removed - student discount always available)
  static Future<double> calculateDiscountedFareWithHoliday(
      double originalFare, String passengerType,
      {DateTime? date}) async {
    // Simply use the regular discount calculation (no holiday check)
    return calculateDiscountedFare(originalFare, passengerType);
  }

  /// Gets the discount amount for display purposes
  static double getDiscountAmount(double originalFare, String passengerType) {
    if (passengerType.isEmpty || passengerType == 'None') {
      return 0.0;
    }
    return originalFare * discountPercentage;
  }

  /// Gets the discount amount for display (holiday rule removed - student discount always available)
  static Future<double> getDiscountAmountWithHoliday(
      double originalFare, String passengerType,
      {DateTime? date}) async {
    // Simply use the regular discount amount calculation (no holiday check)
    return Future.value(getDiscountAmount(originalFare, passengerType));
  }

  /// Calculates fare between two coordinates by computing distance (in km) via map_utils
  static double calculateFareBetween(LatLng start, LatLng end) {
    final distance = calculateDistanceKm(start, end);
    return calculateFare(distance);
  }

  /// Calculates fare for a full polyline by summing segment distances
  static double calculateFareForPolyline(List<LatLng> polyline) {
    double totalDistance = 0.0;
    for (int i = 0; i < polyline.length - 1; i++) {
      totalDistance += calculateDistanceKm(polyline[i], polyline[i + 1]);
    }
    return calculateFare(totalDistance);
  }
}
