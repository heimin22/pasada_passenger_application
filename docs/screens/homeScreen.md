# HomeScreen Documentation

## Overview

The `HomeScreen` is the main screen of the Pasada Passenger App where users can view the map, select pickup and drop-off locations, choose routes, calculate fares, and book rides. It integrates Google Maps, weather data, booking management, real-time driver tracking, and various other features to provide a complete ride-booking experience.

## Location

`lib/screens/homeScreen.dart`

## Key Technologies, APIs, and Backends

### Backend

- **Supabase** (PostgreSQL + Auth): Primary backend for database operations, user authentication, and real-time subscriptions
  - Database tables: `bookings`, `official_routes`, `passengers`, `drivers`, etc.
  - Authentication: Email/password and Google OAuth via Supabase Auth
  - Storage: ID image uploads stored in Supabase Storage buckets
  - Realtime: Driver location updates via Supabase realtime subscriptions

### External APIs

- **Google Maps Flutter SDK**: Map display, location services, and polylines
  - `google_maps_flutter` package for map rendering
  - `google_maps_flutter_android` for Android-specific implementation
  - `flutter_google_maps_webservices` for geocoding and places
- **OpenWeatherMap / Weather API**: Weather data for weather widgets and alerts
- **Custom Backend API** (via `ApiService`): Additional backend endpoints for booking, routing, and fare calculations
  - Base URL configured via `BACKEND_URL` or `API_URL` in `.env`
  - RESTful endpoints: GET/POST/PUT methods with JWT authentication

### Core Services Used

| Service | Purpose |
|---------|---------|
| `BookingService` | Create bookings, manage booking lifecycle, location tracking |
| `FareService` | Calculate fares with discounts and holiday pricing |
| `RouteService` | Load/save selected route to local storage |
| `PolylineService` | Generate polylines between coordinates |
| `DriverAssignmentService` | Real-time driver assignment and tracking |
| `CapacityService` | Vehicle capacity management and seating preferences |
| `LocationWeatherService` | Fetch weather data based on user location |
| `WeatherProvider` | State management for weather data |
| `AllowedStopsServices` | Get allowed stops for selected route |
| `ErrorLoggingService` | Log errors to backend for debugging |
| `NotificationService` | Local and push notifications |
| `HomeScreenInitService` | Initialize home screen resources and dialogs |
| `LocalDatabaseService` | SQLite local database for offline data |
| `EncryptionService` | Encrypt sensitive data before storage |

## Widgets Used

### 1. Scaffold
The root widget providing the basic visual structure.

### 2. Stack
Layers map, header, FAB, and bottom section widgets.

### 3. MapScreen (Custom Widget)
- Google Maps display
- Shows pickup/drop-off markers
- Displays driver location (when assigned)
- Polyline route visualization

### 4. HomeHeaderSection (Custom Widget)
- Displays selected route name
- Weather widget integration
- Calendar button for scheduled bookings
- Route selection tap handler

### 5. HomeScreenFAB (Custom Widget)
- Floating action button to center on current location
- Animates based on booking status
- Positioned above bottom sheet

### 6. HomeBottomSection (Custom Widget)
- Location input fields (pickup/dropoff)
- Fare display
- Payment method selector
- Discount selection
- Seating preference
- Confirm booking button

### 7. HomeBookingSheet (Custom Widget)
- Shows booking confirmation details
- Driver information display
- Vehicle capacity indicator
- Cancel booking option

### 8. RefreshableBottomSheet (Custom Widget)
- Reopens with updated location/fare data
- Supports pull-to-refresh

### 9. Dialogs
- `BookingConfirmationDialog`: Confirm before booking
- `DiscountSelectionDialog`: Select discount type (Student, Senior, PWD)
- `SeatingPreferenceSheet`: Choose Sitting/Standing
- `WeatherAlertDialog`: Weather warnings
- `AlertSequenceDialog`: Multiple alerts in sequence

### 10. ValueNotifiers (State Management)
- `_pickupLocationNotifier`: Selected pickup location
- `_dropoffLocationNotifier`: Selected drop-off location
- `_fareNotifier`: Current calculated fare
- `_paymentMethodNotifier`: Selected payment method
- `_routeNotifier`: Selected route
- `_notificationVisibilityNotifier`: Notification visibility state

## Sample Code

```dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pasada_passenger_app/location/selectedLocation.dart';
import 'package:pasada_passenger_app/managers/booking_manager.dart';
import 'package:pasada_passenger_app/providers/weather_provider.dart';
import 'package:pasada_passenger_app/screens/mapScreen.dart';
import 'package:pasada_passenger_app/services/bookingService.dart';
import 'package:pasada_passenger_app/services/fare_service.dart';
import 'package:pasada_passenger_app/services/home_screen_init_service.dart';
import 'package:pasada_passenger_app/services/route_service.dart';
import 'package:pasada_passenger_app/widgets/home_booking_sheet.dart';
import 'package:pasada_passenger_app/widgets/home_bottom_section.dart';
import 'package:pasada_passenger_app/widgets/home_header_section.dart';
import 'package:pasada_passenger_app/widgets/home_screen_fab.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeScreenStateful();
  }
}

class HomeScreenStateful extends StatefulWidget {
  const HomeScreenStateful({super.key});

  @override
  State<HomeScreenStateful> createState() => HomeScreenPageState();
}

class HomeScreenPageState extends State<HomeScreenStateful>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  
  BookingService? bookingService;
  DriverAssignmentService? driverAssignmentService;
  int? activeBookingId;
  
  SelectedLocation? selectedPickUpLocation;
  SelectedLocation? selectedDropOffLocation;
  bool isSearchingPickup = true;
  
  String? selectedPaymentMethod;
  Map<String, dynamic>? selectedRoute;
  double currentFare = 0.0;
  double originalFare = 0.0;
  
  final ValueNotifier<SelectedLocation?> _pickupLocationNotifier = ValueNotifier(null);
  final ValueNotifier<SelectedLocation?> _dropoffLocationNotifier = ValueNotifier(null);
  final ValueNotifier<double> _fareNotifier = ValueNotifier(0.0);
  final ValueNotifier<String?> _paymentMethodNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> _routeNotifier = ValueNotifier(null);
  
  late BookingManager _bookingManager;
  late AnimationController bookingAnimationController;
  
  @override
  void initState() {
    super.initState();
    _bookingManager = BookingManager(this);
    
    bookingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeHomeScreen();
    });
  }

  Future<void> _initializeHomeScreen() async {
    await HomeScreenInitService.runInitialization(
      context: context,
      getIsInitialized: () => _isInitialized,
      setIsInitialized: () => _isInitialized = true,
      // ... other initialization parameters
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            MapScreen(
              key: mapScreenKey,
              pickUpLocation: selectedPickUpLocation?.coordinates,
              dropOffLocation: selectedDropOffLocation?.coordinates,
              // ... other parameters
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              child: HomeHeaderSection(
                routeName: selectedRoute?['route_name'] ?? 'Select Route',
                onRouteSelectionTap: _showRouteSelection,
              ),
            ),
            HomeScreenFAB(
              onPressed: () { /* center on location */ },
            ),
            HomeBottomSection(
              selectedPickUpLocation: selectedPickUpLocation,
              selectedDropOffLocation: selectedDropOffLocation,
              currentFareNotifier: _fareNotifier,
              onNavigateToLocationSearch: _navigateToLocationSearch,
              onConfirmBooking: _showBookingConfirmationDialog,
            ),
          ],
        ),
      ),
    );
  }
}
```

## How It Works

### 1. Initialization (`initState` and `_initializeHomeScreen`)
- Initializes `BookingManager` for booking lifecycle
- Sets up animation controllers for smooth UI transitions
- Creates ValueNotifiers for reactive state management
- Calls `HomeScreenInitService.runInitialization()` to:
  - Verify user authentication via Supabase
  - Initialize core resources
  - Load saved locations from SharedPreferences
  - Load saved payment method
  - Load saved route
  - Show onboarding dialog on first launch
  - Request notification permissions

### 2. Route Selection (`_showRouteSelection`)
1. Navigates to route selection screen via `navigateToRouteSelection`
2. On route selected:
   - Clears previous pickup/dropoff locations
   - Saves new route to local storage via `RouteService`
   - Queries Supabase for route ID (`official_routes` table)
   - Zooms map to show route bounds

### 3. Location Search (`_navigateToLocationSearch`)
1. Gets current route ID from Supabase
2. Gets route polyline coordinates
3. Finds closest stop for pickup location
4. Navigates to location search screen
5. On location selected:
   - Updates state with new location
   - Saves to SharedPreferences
   - Reopens bottom sheet with updated fare

### 4. Fare Calculation
1. User selects pickup and drop-off locations
2. `MapScreen` calculates distance and base fare
3. `onFareUpdated` callback applies discounts via `FareService.calculateDiscountedFareWithHoliday()`
4. Fare updates in real-time via `_fareNotifier`

### 5. Booking Confirmation (`_showBookingConfirmationDialog`)
1. Shows `BookingConfirmationDialog` with booking details
2. On user confirm:
   - Calls `_bookingManager.handleBookingConfirmation()`
   - Creates booking via `BookingService.createBooking()`
   - Starts polling for driver assignment
   - Shows booking sheet with status

### 6. Booking Lifecycle (`BookingManager`)
- **Requested**: Booking created, waiting for driver
- **Accepted**: Driver assigned, shows driver info
- **Ongoing**: Trip in progress
- **Completed**: Trip finished
- **Cancelled**: Booking cancelled by user or driver

### 7. Real-time Driver Tracking
- `DriverAssignmentService` polls for driver location
- Updates map with driver marker position
- Shows ETA to location

###  pickup8. App Lifecycle Handling (`didChangeAppLifecycleState`)
- On resume: Reload location, reinitialize services, show startup alerts

### 9. Container Measurement
- `measureContainers()` calculates heights for proper widget positioning
- Called after location changes and layout updates

### 10. State Persistence
- Locations saved to `SharedPreferences` as JSON
- Payment method saved to `SharedPreferences`
- Route saved via `RouteService`
- Booking state managed by `BookingManager`

## Dependencies

### Pub Packages
- `package:flutter/material.dart` - Core Flutter widgets
- `package:google_maps_flutter/google_maps_flutter.dart` - Google Maps
- `package:supabase_flutter/supabase_flutter.dart` - Supabase backend
- `package:provider/provider.dart` - State management
- `package:shared_preferences/shared_preferences.dart` - Local storage
- `package:fluttertoast/fluttertoast.dart` - Toast notifications
- `package:flutter/services.dart` - System UI configuration

### Custom Services
- `package:pasada_passenger_app/services/bookingService.dart` - Booking management
- `package:pasada_passenger_app/services/fare_service.dart` - Fare calculation
- `package:pasada_passenger_app/services/route_service.dart` - Route persistence
- `package:pasada_passenger_app/services/home_screen_init_service.dart` - Initialization
- `package:pasada_passenger_app/services/driverAssignmentService.dart` - Driver tracking
- `package:pasada_passenger_app/services/capacity_service.dart` - Capacity management
- `package:pasada_passenger_app/services/location_weather_service.dart` - Weather data
- `package:pasada_passenger_app/providers/weather_provider.dart` - Weather state

### Custom Widgets
- `package:pasada_passenger_app/widgets/home_header_section.dart` - Header with route
- `package:pasada_passenger_app/widgets/home_bottom_section.dart` - Location inputs
- `package:pasada_passenger_app/widgets/home_booking_sheet.dart` - Booking details
- `package:pasada_passenger_app/widgets/home_screen_fab.dart` - Center location FAB

### Other
- `lib/screens/mapScreen.dart` - Map display
- `lib/location/selectedLocation.dart` - Location data model
- `lib/managers/booking_manager.dart` - Booking state management

## Route Names

| Route | Screen |
|-------|--------|
| `home` | HomeScreen (main booking screen) |
| `routeSelection` | Route selection screen |
| `locationSearch` | Location search screen |
| `calendar` | Calendar/scheduling screen |

## Arguments Passed

### To Location Search
```dart
{
  'isPickup': bool,           // true for pickup, false for dropoff
  'routeID': int?,            // Selected route ID
  'routeDetails': Map?,       // Full route information
  'routePolyline': List<LatLng>?, // Route polyline coordinates
  'pickupOrder': int?,        // Pickup stop order (for dropoff search)
  'selectedPickUpLocation': SelectedLocation?,
  'selectedDropOffLocation': SelectedLocation?,
}
```

### Booking Confirmation Data
```dart
{
  'pickupAddress': String,      // Pickup location address
  'pickupCoordinates': LatLng,  // Pickup coordinates
  'dropoffAddress': String,     // Drop-off location address
  'dropoffCoordinates': LatLng,// Drop-off coordinates
  'paymentMethod': String,       // Selected payment method
  'fare': double,               // Calculated fare
  'seatingPreference': String,  // Sitting or Standing
  'discountType': String?,      // Student, Senior, PWD, or null
}
```

## Database Tables (Supabase)

- `bookings` - User bookings
- `official_routes` - Available routes
- `passengers` - User passenger profiles
- `drivers` - Driver information
- `vehicles` - Vehicle details
- `stops` - Route stops
- `holidays` - Holiday dates for fare discounts

## Environment Variables (.env)

- `BACKEND_URL` - Custom backend API URL
- `API_URL` - Alternative API URL
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_ANON_KEY` - Supabase anonymous key
