import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pasada_passenger_app/utils/app_logger.dart';
import 'package:pasada_passenger_app/utils/heading_calculator.dart';

/// Manages directional bus marker with rotation based on driver heading
class MapDirectionalBusManager {
  // Bus marker properties
  BitmapDescriptor? _busIconDefault;
  BitmapDescriptor? _busIconHorizontal;

  // Driver state
  LatLng? _currentPosition;
  double? _currentHeading;
  String? _lastRideStatus;

  // Location history for heading calculation
  final List<LatLng> _locationHistory = [];
  static const int _maxHistorySize = 5;

  // Animation state
  Timer? _rotationTimer;
  double _targetRotation = 0.0;
  double _currentRotation = 0.0;
  bool _isRotating = false;

  // Marker storage
  final Map<MarkerId, Marker> _markers = {};

  // Callbacks
  Function()? onStateChanged;
  Function(String)? onError;

  MapDirectionalBusManager({
    this.onStateChanged,
    this.onError,
  });

  /// Initialize bus icons
  Future<void> initializeBusIcons() async {
    try {
      AppLogger.debug('Starting to load bus icons...', tag: 'BusManager');

      // Load default bus icon (vertical)
      _busIconDefault = await BitmapDescriptor.asset(
        ImageConfiguration(size: Size(48, 48)),
        'assets/png/bus.png',
      );
      AppLogger.debug('Default bus icon loaded: ${_busIconDefault != null}',
          tag: 'BusManager');

      // Load horizontal bus icon
      try {
        _busIconHorizontal = await BitmapDescriptor.asset(
          ImageConfiguration(size: Size(48, 48)),
          'assets/png/bus_h.png',
        );
        AppLogger.debug(
            'Horizontal bus icon loaded: ${_busIconHorizontal != null}',
            tag: 'BusManager');
      } catch (e) {
        AppLogger.warn('Failed to load horizontal bus icon, using default: $e',
            tag: 'BusManager');
        _busIconHorizontal = _busIconDefault; // Fallback to default
      }

      AppLogger.info('Bus icons loaded successfully', tag: 'BusManager');
    } catch (e) {
      AppLogger.error('Error loading bus icons: $e', tag: 'BusManager');
      onError?.call('Failed to load bus icons: ${e.toString()}');
    }
  }

  /// Update driver position with heading
  void updateDriverPosition(LatLng position,
      {double? heading, String? rideStatus}) {
    AppLogger.debug(
        'updateDriverPosition pos:$position heading:$heading status:$rideStatus',
        tag: 'BusManager',
        throttle: true);

    // If status is cancelled, remove the marker
    if (rideStatus == 'cancelled') {
      _markers.remove(MarkerId('driver'));
      _currentPosition = null;
      _lastRideStatus = rideStatus;
      onStateChanged?.call();
      return;
    }

    if (_busIconDefault == null || _busIconHorizontal == null) {
      AppLogger.warn(
          'Bus icons not initialized - Default: ${_busIconDefault != null}, Horizontal: ${_busIconHorizontal != null}',
          tag: 'BusManager');
      onError?.call('Bus icons not initialized');
      return;
    }

    _currentPosition = position;
    _lastRideStatus = rideStatus;

    // Calculate heading from location history if not provided
    double? calculatedHeading = heading;
    if (calculatedHeading == null) {
      _addToLocationHistory(position);
      calculatedHeading = _calculateHeadingFromHistory();
    }

    _currentHeading = calculatedHeading;

    // Update marker with appropriate rotation
    _updateBusMarker(position, calculatedHeading);

    AppLogger.debug('Updated driver position status:$rideStatus',
        tag: 'BusManager', throttle: true);
  }

  /// Update bus marker with rotation
  void _updateBusMarker(LatLng position, double? heading) {
    // quiet: internal marker update

    final driverMarkerId = MarkerId('driver');

    // Determine which icon to use based on heading
    BitmapDescriptor iconToUse = _busIconDefault!;
    double rotation = 0.0;

    if (heading != null) {
      // Convert heading to rotation (0-360 degrees)
      rotation = heading;

      // Use horizontal icon for certain heading ranges for better visibility
      if ((heading >= 45 && heading <= 135) ||
          (heading >= 225 && heading <= 315)) {
        iconToUse = _busIconHorizontal!;
        // quiet
      } else {
        // quiet
      }
    }

    // Create rotated marker
    _markers[driverMarkerId] = Marker(
      markerId: driverMarkerId,
      position: position,
      icon: iconToUse,
      anchor: const Offset(0.5, 0.5),
      rotation: rotation,
    );

    // quiet
    onStateChanged?.call();
  }

  /// Smoothly rotate bus marker to new heading
  void rotateToHeading(double newHeading) {
    if (_currentHeading == null) {
      _currentHeading = newHeading;
      _currentRotation = newHeading;
      return;
    }

    // Calculate shortest rotation path
    double current = _currentHeading!;
    double target = newHeading;

    // Normalize angles to 0-360
    current = current % 360;
    target = target % 360;

    // Calculate shortest rotation
    double diff = target - current;
    if (diff > 180) {
      diff -= 360;
    } else if (diff < -180) {
      diff += 360;
    }

    _targetRotation = current + diff;
    _currentHeading = newHeading;

    // Start smooth rotation animation
    _startRotationAnimation();
  }

  /// Start smooth rotation animation
  void _startRotationAnimation() {
    if (_isRotating) return;

    _isRotating = true;
    const int steps = 20;
    const Duration stepDuration = Duration(milliseconds: 50);

    double startRotation = _currentRotation;
    double rotationDiff = _targetRotation - startRotation;

    int step = 0;
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(stepDuration, (timer) {
      step++;
      final double progress = step / steps;
      final double easedProgress = _easeInOutCubic(progress);

      _currentRotation = startRotation + (rotationDiff * easedProgress);

      // Update marker with new rotation
      if (_currentPosition != null) {
        _updateBusMarker(_currentPosition!, _currentRotation);
      }

      if (step >= steps) {
        _currentRotation = _targetRotation;
        _isRotating = false;
        timer.cancel();
      }
    });
  }

  /// Easing function for smooth rotation
  double _easeInOutCubic(double t) {
    return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
  }

  /// Get current driver marker
  Marker? get driverMarker => _markers[MarkerId('driver')];

  /// Get all markers
  Set<Marker> get allMarkers => Set<Marker>.of(_markers.values);

  /// Get current driver position
  LatLng? get currentPosition => _currentPosition;

  /// Get current heading
  double? get currentHeading => _currentHeading;

  /// Get last ride status
  String? get lastRideStatus => _lastRideStatus;

  /// Check if bus icons are loaded
  bool get areIconsLoaded =>
      _busIconDefault != null && _busIconHorizontal != null;

  /// Check if rotation is in progress
  bool get isRotating => _isRotating;

  /// Force update marker position without rotation
  void forceUpdatePosition(LatLng position) {
    _currentPosition = position;
    _updateBusMarker(position, _currentHeading);
  }

  /// Stop rotation animation
  void stopRotation() {
    _rotationTimer?.cancel();
    _isRotating = false;
  }

  /// Add location to history for heading calculation
  void _addToLocationHistory(LatLng position) {
    _locationHistory.add(position);

    // Keep only recent locations
    if (_locationHistory.length > _maxHistorySize) {
      _locationHistory.removeAt(0);
    }
  }

  /// Calculate heading from location history
  double? _calculateHeadingFromHistory() {
    if (_locationHistory.length < 2) return null;

    // Use smoothed heading calculation
    final double heading =
        HeadingCalculator.calculateSmoothedHeading(_locationHistory);

    AppLogger.debug(
        'Smoothed heading: ${heading.toStringAsFixed(1)}° (${HeadingCalculator.getHeadingDirection(heading)})',
        tag: 'BusManager',
        throttle: true);

    return heading;
  }

  /// Get location history for debugging
  List<LatLng> get locationHistory => List.from(_locationHistory);

  /// Clear location history
  void clearLocationHistory() {
    _locationHistory.clear();
  }

  /// Dispose resources
  void dispose() {
    _rotationTimer?.cancel();
    _markers.clear();
    _locationHistory.clear();
  }
}
