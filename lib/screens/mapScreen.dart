import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pasada_passenger_app/location/selectedLocation.dart';
import 'package:pasada_passenger_app/utils/map_camera_manager.dart';
import 'package:pasada_passenger_app/utils/map_dialog_manager.dart';
import 'package:pasada_passenger_app/utils/map_directional_bus_manager.dart';
import 'package:pasada_passenger_app/utils/map_driver_animation_manager.dart';
import 'package:pasada_passenger_app/utils/map_driver_tracker.dart';
import 'package:pasada_passenger_app/utils/map_location_manager.dart';
import 'package:pasada_passenger_app/utils/map_marker_manager.dart';
import 'package:pasada_passenger_app/utils/map_polyline_state_manager.dart';
import 'package:pasada_passenger_app/utils/map_route_manager.dart';
import 'package:pasada_passenger_app/utils/map_stable_state_manager.dart';
import 'package:pasada_passenger_app/utils/optimized_marker_manager.dart';
import 'package:pasada_passenger_app/utils/optimized_polyline_manager.dart';
import 'package:pasada_passenger_app/widgets/skeleton.dart';

class MapScreen extends StatefulWidget {
  final LatLng? pickUpLocation;
  final LatLng? dropOffLocation;
  final double bottomPadding;
  final Function(String)? onEtaUpdated;
  final Function(double)? onFareUpdated;
  final Function(LatLng)? onLocationUpdated;
  final Map<String, dynamic>? selectedRoute;
  final List<LatLng>? routePolyline;
  final String bookingStatus; // 'requested' | 'accepted' | 'ongoing' | etc.

  const MapScreen({
    super.key,
    this.pickUpLocation,
    this.dropOffLocation,
    this.bottomPadding = 0.07,
    this.onEtaUpdated,
    this.onFareUpdated,
    this.onLocationUpdated,
    this.selectedRoute,
    this.routePolyline,
    this.bookingStatus = 'requested',
  });

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final Completer<GoogleMapController> mapController = Completer();
  LatLng? currentLocation;
  final String apiKey = dotenv.env['ANDROID_MAPS_API_KEY']!;

  @override
  bool get wantKeepAlive => true;

  // Manager instances
  late MapLocationManager _locationManager;
  late MapCameraManager _cameraManager;
  late MapRouteManager _routeManager;
  late MapMarkerManager _markerManager;
  late MapDialogManager _dialogManager;
  late MapDriverTracker _driverTracker;
  late MapPolylineStateManager _polylineStateManager;
  late MapDriverAnimationManager _driverAnimationManager;
  late MapDirectionalBusManager _directionalBusManager;
  late MapStableStateManager _stableStateManager;

  // Optimized managers for better performance
  late OptimizedMarkerManager _optimizedMarkerManager;
  late OptimizedPolylineManager _optimizedPolylineManager;

  // State variables
  LatLng? selectedPickupLatLng;
  LatLng? selectedDropOffLatLng;
  LatLng? driverLocation;
  String? etaText;
  double fareAmount = 0.0;
  bool showRouteEndIndicator = false;
  String routeEndName = '';
  GoogleMapController? _mapController;

  // Coalesced rebuild coordinator to avoid chatty setState calls
  Timer? _rebuildTimer;
  static const Duration _rebuildInterval = Duration(milliseconds: 33); // ~30Hz
  bool _rebuildPending = false;

  // Throttle UI updates for location after initial acquisition
  DateTime? _lastUiLocationRebuild;

  // Camera tightening state
  LatLng? _lastTightenDriverPosition;
  double _currentBoundPadding =
      40.0; // pixels - reduced from 60.0 to prevent excessive bounce
  static const double _minBoundPadding = 20.0; // pixels
  static const double _tightenStep = 8.0; // pixels per 500m

  // Override methods
  /// state of the app
  @override
  void initState() {
    super.initState();
    _initializeManagers();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeMapComponents();
      }
    });
  }

  /// Initialize all manager instances
  void _initializeManagers() {
    // Initialize location manager
    _locationManager = MapLocationManager(
      onLocationUpdated: (location) {
        if (mounted) {
          // First fix: only trigger a full rebuild on first location set.
          if (currentLocation == null) {
            setState(() => currentLocation = location);
          } else {
            // Update without forcing an immediate rebuild every tick.
            currentLocation = location;
            // Throttle UI rebuilds to ~30Hz.
            final now = DateTime.now();
            if (_lastUiLocationRebuild == null ||
                now.difference(_lastUiLocationRebuild!) >= _rebuildInterval) {
              _requestCoalescedRebuild();
              _lastUiLocationRebuild = now;
            }
          }
          widget.onLocationUpdated?.call(location);
        }
      },
      onError: (error) => _dialogManager.showError(error),
      onLocationPermissionDenied: () =>
          _dialogManager.showLocationPermissionDialog(),
      onLocationServiceDisabled: () => _dialogManager.showLocationErrorDialog(
        onRetry: () => _locationManager.initializeLocation(),
      ),
      onPrePromptLocationPermission: () =>
          _dialogManager.showPrePromptLocationPermission(),
      onPrePromptLocationService: () =>
          _dialogManager.showPrePromptLocationService(),
    );

    // Initialize camera manager
    _cameraManager = MapCameraManager(
      mapController: mapController,
      onAnimationStateChanged: (isAnimating) {
        _requestCoalescedRebuild();
      },
    );
    // Initialize marker manager
    _markerManager = MapMarkerManager(
      onStateChanged: () {
        _requestCoalescedRebuild();
      },
    );

    // Initialize dialog manager
    _dialogManager = MapDialogManager(context);

    // Initialize polyline state manager
    _polylineStateManager = MapPolylineStateManager(
      onStateChanged: () {
        // Keep polyline-related behavior unchanged.
        if (mounted) setState(() {});
      },
      onError: (error) => _dialogManager.showError(error),
    );

    // Initialize driver animation manager
    _driverAnimationManager = MapDriverAnimationManager(
      onStateChanged: () {
        _requestCoalescedRebuild();
      },
      onError: (error) => _dialogManager.showError(error),
    );

    // Initialize directional bus manager
    _directionalBusManager = MapDirectionalBusManager(
      onStateChanged: () {
        _requestCoalescedRebuild();
      },
      onError: (error) => _dialogManager.showError(error),
    );

    // Initialize stable state manager
    _stableStateManager = MapStableStateManager(
      onStateChanged: () {
        // Don't call setState - use ValueListenableBuilder instead
      },
      onError: (error) => _dialogManager.showError(error),
    );

    // Initialize optimized managers
    _optimizedMarkerManager = OptimizedMarkerManager(
      onStateChanged: () {
        // Don't call setState - use ValueListenableBuilder instead
      },
      onError: (error) => _dialogManager.showError(error),
    );

    _optimizedPolylineManager = OptimizedPolylineManager(
      onStateChanged: () {
        // Don't call setState - use ValueListenableBuilder instead
      },
      onError: (error) => _dialogManager.showError(error),
    );

    // Initialize route manager with optimized polyline manager
    _routeManager = MapRouteManager(
      onFareUpdated: (fare) {
        fareAmount = fare;
        widget.onFareUpdated?.call(fare);
        _requestCoalescedRebuild();
      },
      onError: (error) => _dialogManager.showError(error),
      onStateChanged: () {
        _requestCoalescedRebuild();
      },
      optimizedPolylineManager: _optimizedPolylineManager,
    );

    // Initialize driver tracker
    _driverTracker = MapDriverTracker(
      onDriverRouteUpdated: (driverLocation, route) {
        // Use optimized polyline manager for better performance
        _optimizedPolylineManager.updatePolyline(
          const PolylineId('driver_route_live'),
          route,
          color: const Color.fromARGB(255, 10, 179, 83),
          width: 4,
        );
      },
      onError: (error) => _dialogManager.showError(error),
    );
  }

  /// Initialize map components after managers are ready
  Future<void> _initializeMapComponents() async {
    // Initialize marker icons
    await _markerManager.initializeIcons();

    // Initialize driver animation manager
    await _driverAnimationManager.initializeBusIcon();

    // Initialize directional bus manager
    await _directionalBusManager.initializeBusIcons();

    // Test: Create a marker at a default location to verify icons are working
    if (currentLocation != null) {
      _directionalBusManager.updateDriverPosition(currentLocation!,
          rideStatus: 'test');
    }

    // Remove any existing driver markers from stable state manager
    _stableStateManager.removeDriverMarker();

    // Remove any existing driver markers from marker manager
    _markerManager.removeDriverMarker();

    // Initialize camera manager with map controller
    _cameraManager.initialize(mapController);

    // Load cached location and animate to it
    final cachedLocation = await _locationManager.getCachedLocation();
    if (cachedLocation != null && mounted) {
      setState(() => currentLocation = cachedLocation);
      await _cameraManager.animateToLocation(cachedLocation);
    }

    // Initialize location tracking
    await _locationManager.initializeLocation();

    // Handle route updates based on widget parameters
    handleLocationUpdates();
  }

  /// disposing of functions
  @override
  void dispose() {
    _rebuildTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _mapController?.dispose();
    _locationManager.dispose();
    _cameraManager.dispose();
    _routeManager.dispose();
    _markerManager.dispose();
    _driverTracker.dispose();
    _polylineStateManager.dispose();
    _driverAnimationManager.dispose();
    _directionalBusManager.dispose();
    _stableStateManager.dispose();

    // Dispose optimized managers
    _optimizedMarkerManager.dispose();
    _optimizedPolylineManager.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // here once the app is opened,
    // intiate the location and get the location updates
    final isScreenActive = state == AppLifecycleState.resumed;
    _locationManager.setScreenActive(isScreenActive);

    if (isScreenActive) {
      handleLocationUpdates();
    }
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    // get the location from previous widget
    // then call the handleLocationUpdates
    super.didUpdateWidget(oldWidget);
    if (widget.pickUpLocation != oldWidget.pickUpLocation ||
        widget.dropOffLocation != oldWidget.dropOffLocation) {
      handleLocationUpdates();
    }

    // Auto-bind camera when status changes to accepted/ongoing
    if (widget.bookingStatus != oldWidget.bookingStatus &&
        (widget.bookingStatus == 'accepted' ||
            widget.bookingStatus == 'ongoing')) {
      // Reset tightening state when entering tracking statuses
      _lastTightenDriverPosition = null;
      _currentBoundPadding =
          40.0; // Reduced from 60.0 to prevent excessive bounce
      // Attempt immediate focus if we have positions
      // This schedules after build to ensure map is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDriverFocusBounds(widget.bookingStatus);
      });
    }
  }

  void calculateRoute() {
    //  make sure there's a null check before placing polylines
    if (selectedPickupLatLng == null || selectedDropOffLatLng == null) {
      _dialogManager.showLocationSelectionRequired();
      return;
    }
    // generate the polylines calling selectedPickupLatlng and selectedDropOffLatLng
    _renderRouteBetween(selectedPickupLatLng!, selectedDropOffLatLng!);
  }

  // handle yung location updates for the previous widget to generate polylines
  Future<void> handleLocationUpdates() async {
    // Suppress drawing selection polylines while a ride is accepted/ongoing
    if (widget.bookingStatus == 'accepted' ||
        widget.bookingStatus == 'ongoing') {
      return;
    }
    if (widget.pickUpLocation != null && widget.dropOffLocation != null) {
      if (widget.routePolyline?.isNotEmpty == true) {
        final segment = await _routeManager.renderRouteAlongPolyline(
          widget.pickUpLocation!,
          widget.dropOffLocation!,
          widget.routePolyline!,
        );

        if (segment.isNotEmpty) {
          // Use optimized polyline manager for better performance
          _optimizedPolylineManager.updatePolyline(
            const PolylineId('route'),
            segment,
            color: const Color(0xFF00CC58),
            width: 4,
          );

          // Zoom camera to the segment bounds
          await _cameraManager.moveCameraToRoute(
            segment,
            widget.pickUpLocation!,
            widget.dropOffLocation!,
          );
        }
      } else {
        final route = await _routeManager.renderRouteBetween(
          widget.pickUpLocation!,
          widget.dropOffLocation!,
        );

        if (route.isNotEmpty) {
          // Use optimized polyline manager for better performance
          _optimizedPolylineManager.updatePolyline(
            const PolylineId('route'),
            route,
            color: const Color(0xFF00CC58),
            width: 4,
          );

          await _cameraManager.moveCameraToRoute(
            route,
            widget.pickUpLocation!,
            widget.dropOffLocation!,
          );
        }
      }
    }
  }

  // animate yung current location marker
  void pulseCurrentLocationMarker() {
    if (!mounted) return;
    _cameraManager.pulseCurrentLocationMarker();
  }

  Future<bool> checkPickupDistance(LatLng pickupLocation) async {
    if (currentLocation == null) return true;

    return await _dialogManager.showPickupDistanceWarning(
      pickupLocation,
      currentLocation!,
    );
  }

  Future<void> handleSearchLocationSelection(
      SelectedLocation location, bool isPickup) async {
    if (isPickup) {
      final shouldProceed = await checkPickupDistance(location.coordinates);
      if (!shouldProceed) return;
    }
    if (isPickup) {
      setState(() {
        selectedPickupLatLng = location.coordinates;
        // Update any other necessary pickup-related state
      });
    } else {
      setState(() {
        selectedDropOffLatLng = location.coordinates;
        // Update any other necessary dropoff-related state
      });
    }
  }

  // animate yung camera papunta sa current location ng user
  Future<void> animateToLocation(LatLng target) async {
    await _cameraManager.animateToLocation(target);
  }

  // ito yung method para sa pick-up and drop-off location
  Future<void> updateLocations(
      {LatLng? pickup, LatLng? dropoff, bool skipDistanceCheck = false}) async {
    // Suppress drawing selection polylines while a ride is accepted/ongoing
    if (widget.bookingStatus == 'accepted' ||
        widget.bookingStatus == 'ongoing') {
      return;
    }
    if (pickup != null) {
      if (!skipDistanceCheck) {
        final shouldProceed = await checkPickupDistance(pickup);
        if (!shouldProceed) return;
      }
      selectedPickupLatLng = pickup;
    }

    if (dropoff != null) selectedDropOffLatLng = dropoff;

    if (selectedPickupLatLng != null && selectedDropOffLatLng != null) {
      List<LatLng> route = [];

      if (widget.routePolyline?.isNotEmpty == true) {
        route = await _routeManager.renderRouteAlongPolyline(
          selectedPickupLatLng!,
          selectedDropOffLatLng!,
          widget.routePolyline!,
        );

        if (route.isNotEmpty) {
          _optimizedPolylineManager.updatePolyline(
            const PolylineId('route'),
            route,
            color: const Color(0xFF00CC58),
            width: 4,
          );
        }
      } else {
        // Direct route fallback
        route = await _routeManager.renderRouteBetween(
          selectedPickupLatLng!,
          selectedDropOffLatLng!,
        );

        if (route.isNotEmpty) {
          _optimizedPolylineManager.updatePolyline(
            const PolylineId('route'),
            route,
            color: const Color(0xFF00CC58),
            width: 4,
          );
        }
      }

      if (route.isNotEmpty) {
        await _cameraManager.moveCameraToRoute(
          route,
          selectedPickupLatLng!,
          selectedDropOffLatLng!,
        );
      }
    }
  }

  Future<bool> checkNetworkConnection() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      _dialogManager.showNetworkError();
      return false;
    }
    return true;
  }

  // Helper method for backward compatibility
  Future<void> _renderRouteBetween(LatLng start, LatLng destination) async {
    // Suppress drawing selection polylines while a ride is accepted/ongoing
    if (widget.bookingStatus == 'accepted' ||
        widget.bookingStatus == 'ongoing') {
      return;
    }
    final route = await _routeManager.renderRouteBetween(start, destination);
    if (route.isNotEmpty) {
      // Update polyline in optimized manager
      _optimizedPolylineManager.updatePolyline(
        const PolylineId('route'),
        route,
        color: const Color(0xFF00CC58),
        width: 4,
      );
      await _cameraManager.moveCameraToRoute(route, start, destination);
    }
  }

  // Expose camera bounds zoom for external callers
  Future<void> zoomToBounds(List<LatLng> polylineCoordinates) async {
    await _cameraManager.zoomToBounds(polylineCoordinates);
  }

  // Show bounds between driver and pickup/dropoff depending on ride status
  Future<void> showDriverFocusBounds(String rideStatus) async {
    if (driverLocation == null) return;
    final LatLng? target = rideStatus == 'accepted'
        ? widget.pickUpLocation
        : widget.dropOffLocation;
    if (target == null) return;
    await _cameraManager.showPickupAndDropoff(
      driverLocation!,
      target,
      boundPadding: _currentBoundPadding,
    );
  }

  void onMapCreated(GoogleMapController controller) {
    mapController.complete(controller);
  }

  // Schedules a coalesced rebuild at most once per _rebuildInterval
  void _requestCoalescedRebuild() {
    if (!mounted) return;
    if (_rebuildPending) return;
    _rebuildPending = true;
    _rebuildTimer?.cancel();
    _rebuildTimer = Timer(_rebuildInterval, () {
      if (!mounted) return;
      _rebuildPending = false;
      // Rebuild only once for any number of upstream notifications in the window
      setState(() {});
    });
  }

  // Add this method to update map style
  void _updateMapStyle() {
    if (_mapController == null) return;
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _updateMapStyle();
  }

  // Update driver marker and draw road-following polyline to pickup/dropoff
  Future<void> updateDriverLocation(LatLng location, String rideStatus,
      {double? heading}) async {
    if (!mounted) return;

    // Don't update if ride is cancelled
    if (rideStatus == 'cancelled') {
      // Clear driver from map if cancelled
      _clearDriverFromMap();
      return;
    }

    // Update driver location using stable state manager (prevents flickering)
    _stableStateManager.updateDriverLocation(location, rideStatus);

    // Remove any existing driver markers from stable state manager
    _stableStateManager.removeDriverMarker();

    // Remove any existing driver markers from marker manager
    _markerManager.removeDriverMarker();

    // Update directional bus marker with heading
    // quiet: reduce verbose logging in production
    _directionalBusManager.updateDriverPosition(location,
        heading: heading, rideStatus: rideStatus);

    // Update local state for other components
    driverLocation = location;

    // Handle status-specific UI changes
    if (rideStatus == 'accepted') {
      _markerManager.removeMarker('route_destination');
      showRouteEndIndicator = false;

      // Remove any existing pickup->dropoff polylines
      _routeManager.removePolyline(const PolylineId('route'));
      _routeManager.removePolyline(const PolylineId('route_path'));
    }

    // Use driver tracker to handle route generation and caching
    // This will update polylines through the stable state manager
    await _driverTracker.updateDriverLocation(
      location,
      rideStatus,
      pickupLocation: widget.pickUpLocation,
      dropoffLocation: widget.dropOffLocation,
    );

    // Enforce polyline whitelist to prevent duplicate/stale overlays
    _enforcePolylineWhitelist(rideStatus);

    // Auto-bind camera between driver and pickup/dropoff for accepted/ongoing
    if (rideStatus == 'accepted' || rideStatus == 'ongoing') {
      // Initial bind
      if (_lastTightenDriverPosition == null) {
        _lastTightenDriverPosition = location;
        await showDriverFocusBounds(rideStatus);
      } else {
        // Tighten every 500m of driver movement
        final movedKm =
            calculateDistance(_lastTightenDriverPosition!, location);
        if (movedKm >= 0.5 && _currentBoundPadding > _minBoundPadding) {
          _lastTightenDriverPosition = location;
          _currentBoundPadding = (_currentBoundPadding - _tightenStep)
              .clamp(_minBoundPadding, 120.0);
          await showDriverFocusBounds(rideStatus);
        }
      }
    }
  }

  // Helper to generate and update polyline for driver route without clearing other polylines
  // Driver route generation is handled by RideService; remove inline implementation.

  Set<Marker> buildMarkers() {
    final markers = _markerManager.buildMarkers(
      pickupLocation: widget.pickUpLocation,
      dropoffLocation: widget.dropOffLocation,
      driverLocation: null, // Don't use regular driver marker
    );

    // Add directional bus marker if available
    final busMarker = _directionalBusManager.driverMarker;
    if (busMarker != null) {
      markers.add(busMarker);
    }

    // Add markers from stable state manager
    markers.addAll(_stableStateManager.markers);

    return markers;
  }

  // Public interface methods for external access
  /// Animate route drawing (delegates to route manager)
  void animateRouteDrawing(
    PolylineId id,
    List<LatLng> fullRoute,
    Color color,
    int width,
  ) {
    _routeManager.animateRouteDrawing(id, fullRoute, color, width);
  }

  /// Initialize location services (delegates to location manager)
  Future<void> initializeLocation() async {
    await _locationManager.initializeLocation();
  }

  /// Check if location is initialized (delegates to location manager)
  bool get isLocationInitialized => _locationManager.isLocationInitialized;

  /// Move camera to show booking bounds (driver, pickup, dropoff)
  Future<void> showBookingBounds() async {
    if (widget.pickUpLocation == null || widget.dropOffLocation == null) return;

    await _cameraManager.showBookingBounds(
      driverLocation,
      widget.pickUpLocation!,
      widget.dropOffLocation!,
    );
  }

  // Helper methods that delegate to managers
  LatLng findNearestPointOnRoute(LatLng point, List<LatLng> routePolyline) {
    return _routeManager.findNearestPointOnRoute(point, routePolyline);
  }

  double calculateDistance(LatLng point1, LatLng point2) {
    return _routeManager.calculateDistance(point1, point2);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_locationManager.isLocationInitialized) {
        _locationManager.initializeLocation();
      }
    });

    return Scaffold(
      body: RepaintBoundary(
        child: Stack(
          children: [
            ValueListenableBuilder<Set<Polyline>>(
              valueListenable: _optimizedPolylineManager.polylinesNotifier,
              builder: (context, polylines, child) {
                return ValueListenableBuilder<Set<Marker>>(
                  valueListenable: _optimizedMarkerManager.markersNotifier,
                  builder: (context, optimizedMarkers, child) {
                    // Combine optimized markers with stable markers
                    final allMarkers = <Marker>{};
                    allMarkers.addAll(optimizedMarkers);

                    // Add regular markers for pickup/dropoff
                    allMarkers.addAll(_markerManager.buildMarkers(
                      pickupLocation: widget.pickUpLocation,
                      dropoffLocation: widget.dropOffLocation,
                      driverLocation: null, // Don't use regular driver marker
                    ));

                    // Add directional bus marker if available
                    final busMarker = _directionalBusManager.driverMarker;
                    if (busMarker != null) {
                      allMarkers.add(busMarker);
                    }
                    return RepaintBoundary(
                      child: GoogleMap(
                        onMapCreated: (controller) {
                          _mapController = controller;
                          mapController.complete(controller);
                        },
                        cameraTargetBounds: CameraTargetBounds(
                          LatLngBounds(
                            southwest: LatLng(4.215806, 116.928055),
                            northeast: LatLng(21.321780, 126.604363),
                          ),
                        ),
                        style: isDarkMode
                            ? '''[
        {
          "elementType": "geometry",
          "stylers": [{"color": "#1f2c4d"}]
        },
        {
          "elementType": "labels.text.fill",
          "stylers": [{"color": "#8ec3b9"}]
        },
        {
          "elementType": "labels.text.stroke",
          "stylers": [{"color": "#1a3646"}]
        },
        {
          "featureType": "administrative.country",
          "elementType": "geometry.stroke",
          "stylers": [{"color": "#4e4e4e"}]
        },
        {
          "featureType": "administrative.land_parcel",
          "elementType": "labels.text.fill",
          "stylers": [{"color": "#64779e"}]
        },
        {
          "featureType": "poi",
          "elementType": "geometry",
          "stylers": [{"color": "#283d6a"}]
        },
        {
          "featureType": "poi",
          "elementType": "labels.text.fill",
          "stylers": [{"color": "#6f9ba5"}]
        },
        {
          "featureType": "poi.park",
          "elementType": "geometry.fill",
          "stylers": [{"color": "#023e58"}]
        },
        {
          "featureType": "poi.park",
          "elementType": "labels.text.fill",
          "stylers": [{"color": "#3c7680"}]
        },
        {
          "featureType": "road",
          "elementType": "geometry",
          "stylers": [{"color": "#304a7d"}]
        },
        {
          "featureType": "road",
          "elementType": "labels.text.fill",
          "stylers": [{"color": "#98a5be"}]
        },
        {
          "featureType": "road",
          "elementType": "labels.text.stroke",
          "stylers": [{"color": "#1f2835"}]
        },
        {
          "featureType": "transit",
          "elementType": "geometry",
          "stylers": [{"color": "#2f3948"}]
        },
        {
          "featureType": "transit.station",
          "elementType": "labels.text.fill",
          "stylers": [{"color": "#d59563"}]
        },
        {
          "featureType": "water",
          "elementType": "geometry",
          "stylers": [{"color": "#17263c"}]
        },
        {
          "featureType": "water",
          "elementType": "labels.text.fill",
          "stylers": [{"color": "#515c6d"}]
        },
        {
          "featureType": "water",
          "elementType": "labels.text.stroke",
          "stylers": [{"color": "#17263c"}]
        }
      ]'''
                            : '',
                        initialCameraPosition: CameraPosition(
                          target: currentLocation ??
                              const LatLng(14.5995, 120.9842),
                          zoom: currentLocation != null ? 15.0 : 10.0,
                        ),
                        markers: allMarkers,
                        polylines: polylines,
                        padding: EdgeInsets.only(
                          bottom: screenHeight * widget.bottomPadding,
                          left: screenWidth * 0.04,
                        ),
                        mapType: MapType.normal,
                        buildingsEnabled: false,
                        myLocationButtonEnabled:
                            false, // Disabled - using custom Location FAB instead
                        indoorViewEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: true,
                        trafficEnabled: false,
                        rotateGesturesEnabled: true,
                        myLocationEnabled: currentLocation != null,
                      ),
                    );
                  },
                );
              },
            ),
            if (currentLocation == null)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    color: Colors.transparent,
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 16,
                      left: screenWidth * 0.06,
                      right: screenWidth * 0.06,
                      bottom: screenHeight * widget.bottomPadding + 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SkeletonCircle(size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SkeletonLine(
                                  width: screenWidth * 0.6, height: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SkeletonLine(width: screenWidth * 0.4, height: 14),
                        const Spacer(),
                        // Bottom controls placeholder (where pick/drop UI usually sits)
                        SkeletonBlock(
                          width: double.infinity,
                          height: 90,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Clears pickup-to-dropoff polylines when ride is ongoing
  void clearPickupToDropoffPolylines() {
    setState(() {
      // Remove the main route polyline (pickup to dropoff)
      _routeManager.removePolyline(const PolylineId('route'));
      _polylineStateManager.removePolyline(const PolylineId('route'));
      _stableStateManager.removePolyline(const PolylineId('route'));
      _optimizedPolylineManager.removePolyline(const PolylineId('route'));
    });
  }

  // Keep only the relevant polylines depending on ride status
  void _enforcePolylineWhitelist(String rideStatus) {
    final currentPolylines = _optimizedPolylineManager.polylinesNotifier.value;
    if (currentPolylines.isEmpty) return;

    // Whitelist IDs
    final keepIds = <PolylineId>{
      if (rideStatus == 'accepted' || rideStatus == 'ongoing')
        const PolylineId('driver_route_live')
      else
        const PolylineId('route'),
    };

    for (final poly in currentPolylines) {
      if (!keepIds.contains(poly.polylineId)) {
        _optimizedPolylineManager.removePolyline(poly.polylineId);
      }
    }
  }

  // Clears driver from map (used when cancelling)
  void _clearDriverFromMap() {
    if (!mounted) return;
    setState(() {
      driverLocation = null;
      // Clear from all marker managers
      _stableStateManager.removeDriverMarker();
      _markerManager.removeDriverMarker();
      _optimizedMarkerManager.removeMarker('driver');
      // Clear driver route polylines by updating with cancelled status
      _driverTracker.updateDriverLocation(
        const LatLng(0, 0), // Dummy location
        'cancelled',
      );
      // Clear directional bus marker by updating with cancelled status
      _directionalBusManager.updateDriverPosition(
        const LatLng(0, 0),
        rideStatus: 'cancelled',
      );
      // Clear driver route polylines
      _stableStateManager.removePolyline(const PolylineId('driver_route_live'));
      _optimizedPolylineManager
          .removePolyline(const PolylineId('driver_route_live'));
    });
    _requestCoalescedRebuild();
  }

  // Clears all map overlays and selected locations
  void clearAll() {
    setState(() {
      selectedPickupLatLng = null;
      selectedDropOffLatLng = null;
      driverLocation = null; // Clear driver location
      _routeManager.clearAllPolylines();
      _polylineStateManager.clearAllPolylines();
      _stableStateManager.clearAll();
      _optimizedPolylineManager.clearAllPolylines();
      _optimizedMarkerManager.clearAllMarkers();
      _markerManager.clearAllMarkers();
      _driverAnimationManager.dispose();
      _directionalBusManager.dispose();
      fareAmount = 0.0;
      etaText = null;
    });
  }
}
