# IntroductionScreen Documentation

## Overview

The `IntroductionScreen` is the initial landing screen of the Pasada Passenger App. It serves as a welcome screen that displays a greeting message and provides navigation options for user authentication (Log In or Create Account). The screen also handles location permission requests on first launch.

## Location

`lib/screens/introductionScreen.dart`

## Widgets Used

### 1. Scaffold
The root widget that provides the basic visual structure.

### 2. Container
- Wraps the body content
- Applies a time-based gradient background that changes based on the time of day:
  - **Morning (5 AM - 12 PM)**: Blue-green gradient (`#236078` to `#439464`)
  - **Afternoon (12 PM - 6 PM)**: Gold-green gradient (`#CFA425` to `#26AB37`)
  - **Evening (6 PM - 10 PM)**: Purple-brown gradient (`#B45F4F` to `#705776`)
  - **Night (10 PM - 5 AM)**: Dark blue-gray gradient (`#2E3B4E` to `#1C1F2E`)

### 3. SafeArea
Ensures content is positioned within the safe area of the device (notches, status bars, etc.).

### 4. Column
Organizes widgets vertically.

### 5. SlideTransition & FadeTransition
- **AnimationController**: Controls the 1200ms animation duration
- **SlideAnimation**: Slides content up from 30% offset to final position
- **FadeAnimation**: Fades content from 0 to 1 opacity
- Uses `Curves.easeOut` for smooth animation

### 6. Text Widgets
- **Title**: "Kumusta!" (Filipino for "Hello!") - 56px, bold, white
- **Subtitle**: "Sakay ka na, boss!" (Filipino for "Ride now, boss!") - 18px, light gray

### 7. ElevatedButton (Log In)
- Background: Green (`#00CC58`)
- Full width with 56px height
- 14px border radius
- Navigates to: `loginAccount` route

### 8. ElevatedButton (Create Account)
- Background: Transparent white (12% opacity)
- White border (30% opacity, 1.5px width)
- Full width with 56px height
- 14px border radius
- Navigates to: `createAccount` route

### 9. AlertDialog
- **Title**: "Location Access" with icon
- **Content**: Explains why location access is needed
- **Info Box**: Orange warning about permission requirement
- **Action Button**: "Allow" button to trigger location permission

## Sample Code

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:location/location.dart';
import 'package:pasada_passenger_app/services/location_permission_manager.dart';

class IntroductionScreen extends StatefulWidget {
  const IntroductionScreen({super.key});

  @override
  State<IntroductionScreen> createState() => _IntroductionScreenState();
}

class _IntroductionScreenState extends State<IntroductionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _askedLocationOnce = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();

    // Set status bar to white icons
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    // Ask for location on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_askedLocationOnce) {
        _askedLocationOnce = true;
        _showLocationPrePrompt();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: _getTimeBasedGradient(),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                Expanded(
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(height: 60),
                          Text(
                            'Kumusta!',
                            style: TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF5F5F5),
                              fontFamily: 'Inter',
                              height: 1.1,
                              letterSpacing: -1.0,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Sakay ka na, boss!',
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              fontSize: 18,
                              color: Color(0xFFE0E0E0),
                              fontFamily: 'Inter',
                              letterSpacing: 0.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Buttons at the bottom
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pushNamed(context, 'loginAccount');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00CC58),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 56),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Log In'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pushNamed(context, 'createAccount');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.12),
                              foregroundColor: const Color(0xFFF5F5F5),
                              minimumSize: const Size(double.infinity, 56),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            child: const Text('Create Account'),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

## How It Works

### 1. Initialization (`initState`)
- Creates an `AnimationController` with 1200ms duration
- Sets up slide and fade animations with `Curves.easeOut`
- Starts the animation with `_animationController.forward()`
- Configures the status bar style (white icons on dark background)
- Triggers location permission prompt after the first frame

### 2. Time-Based Gradient (`_getTimeBasedGradient`)
The screen dynamically changes its background gradient based on the current hour:
- Morning: Blue-green tones
- Afternoon: Gold-green tones  
- Evening: Purple-brown tones
- Night: Dark blue-gray tones

### 3. Location Permission Flow (`_showLocationPrePrompt`)
1. Checks if location service and permissions are already granted
2. If already granted, skips the dialog
3. If user has already been prompted before, skips the dialog
4. Shows an `AlertDialog` explaining why location is needed
5. On "Allow" button press, calls `ensureLocationReady()` to request system permissions
6. Shows a SnackBar if location cannot be enabled

### 4. Navigation
- **Log In Button**: Navigates to `'loginAccount'` route via `Navigator.pushNamed`
- **Create Account Button**: Navigates to `'createAccount'` route via `Navigator.pushNamed`

## Dependencies

- `package:flutter/material.dart` - Core Flutter widgets
- `package:flutter/services.dart` - System UI configuration
- `package:location/location.dart` - Location services
- `package:pasada_passenger_app/services/location_permission_manager.dart` - Custom location permission handler

## Route Names

| Route | Screen |
|-------|--------|
| `loginAccount` | Login screen |
| `createAccount` | Account creation screen |
