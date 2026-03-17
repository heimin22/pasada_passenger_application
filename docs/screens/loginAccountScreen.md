# LoginAccountScreen Documentation

## Overview

The `LoginAccountScreen` is the authentication screen that allows existing users to log in to the Pasada Passenger App. It supports both email/password authentication and Google sign-in, with features for network connectivity monitoring and responsive design.

## Location

`lib/authentication/loginAccount.dart`

## Widgets Used

### 1. Scaffold
The root widget that provides the basic visual structure with `resizeToAvoidBottomInset` enabled for keyboard handling.

### 2. Container
- Wraps the body content
- Applies a time-based gradient background (same as IntroductionScreen):
  - **Morning (5 AM - 12 PM)**: Blue-green gradient (`#236078` to `#439464`)
  - **Afternoon (12 PM - 6 PM)**: Gold-green gradient (`#CFA425` to `#26AB37`)
  - **Evening (6 PM - 10 PM)**: Purple-brown gradient (`#B45F4F` to `#705776`)
  - **Night (10 PM - 5 AM)**: Dark blue-gray gradient (`#2E3B4E` to `#1C1F2E`)

### 3. SafeArea
Ensures content is positioned within the safe area of the device.

### 4. IconButton (Back Button)
- Navigates back to the previous screen
- Icon: `Icons.arrow_back`
- Color: White (`#F5F5F5`)

### 5. Image (Logo)
- Displays the Pasada white brand logo
- Height: 50-60px (responsive)
- Asset: `assets/png/pasada_white_brand.png`

### 6. Text Widgets
- **Header**: "Welcome Back" - 28-32px, bold, white
- **Subtitle**: "Sign in na para makapagbook ka ulit." - 14-16px, light gray
- **Labels**: "Email Address", "Password" - 14-15px, bold, white

### 7. TextField (Email Input)
- Placeholder: "Enter your email"
- Prefix icon: `Icons.email_outlined`
- Background: White with 12% opacity
- Border: 1.5px white with 30% opacity (default), 2px green (focused)
- Border radius: 14px
- Cursor color: Green (`#00CC58`)

### 8. TextField (Password Input)
- Placeholder: "Enter your password"
- Prefix icon: `Icons.lock_outlined`
- Suffix icon: Visibility toggle (`visibility_outlined` / `visibility_off_outlined`)
- Same styling as email input

### 9. ElevatedButton (Log In)
- Background: Green (`#00CC58`)
- Full width with 50-56px height (responsive)
- 14px border radius
- Loading state: CircularProgressIndicator
- Text: "Log In" - 15-17px, bold, white

### 10. ElevatedButton (Continue with Google)
- Background: Transparent white (12% opacity)
- White border (30% opacity, 1.5px width)
- Full width with 50-56px height (responsive)
- 14px border radius
- Icon: Google SVG icon
- Text: "Continue with Google"

### 11. GestureDetector (Forgot Password)
- Text: "Forgot Password?"
- Color: Green (`#00CC58`)
- Underline decoration
- Navigates to: `ChangeForgottenPassword` route

### 12. SvgPicture (Or Design)
- Asset: `assets/svg/otherOptionsOptimized.svg`
- Divider with "or" text

## Sample Code

```dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pasada_passenger_app/main.dart';
import 'package:pasada_passenger_app/screens/forgotPasswordScreen.dart';
import 'package:pasada_passenger_app/screens/selectionScreen.dart';
import 'package:pasada_passenger_app/services/authService.dart';
import 'package:pasada_passenger_app/utils/toast_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginAccountPage extends StatefulWidget {
  const LoginAccountPage({super.key});

  @override
  State<LoginAccountPage> createState() => _LoginAccountPageState();
}

class _LoginAccountPageState extends State<LoginAccountPage> {
  @override
  Widget build(BuildContext context) {
    return const LoginPage(title: 'Pasada');
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.title});

  final String title;

  @override
  State<LoginPage> createState() => LoginScreen();
}

class LoginScreen extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final AuthService authService = AuthService();
  final session = supabase.auth.currentSession;

  bool isPasswordVisible = false;
  String errorMessage = '';
  bool isLoading = false;

  final Connectivity connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> connectivitySubscription;

  @override
  void initState() {
    super.initState();
    checkInitialConnectivity();
    connectivitySubscription =
        connectivity.onConnectivityChanged.listen(updateConnectionStatus);
  }

  // ... (rest of the implementation)
}
```

## How It Works

### 1. Initialization (`initState`)
- Checks initial network connectivity
- Sets up listener for connectivity changes
- Configures status bar style (white icons)

### 2. Email/Password Login (`login`)
1. Validates that all fields are filled
2. Validates email format using regex
3. Checks network connectivity
4. Attempts sign-in via Supabase auth
5. On success: Shows success toast and navigates to selectionScreen
6. On error: Shows user-friendly error message via ToastUtils

### 3. Google Sign-In (`buildLoginGoogle`)
1. Checks network connectivity
2. Shows "Signing in with Google..." info toast
3. Calls `authService.signInWithGoogle()`
4. On success: Navigates to selectionScreen
5. On cancellation/failure: Shows appropriate error message

### 4. Network Monitoring
- Initial connectivity check on screen load
- Real-time connectivity listener updates
- Shows error toast on connection loss

### 5. Password Visibility Toggle
- Toggle between visible/hidden password
- Uses `Icons.visibility_outlined` and `Icons.visibility_off_outlined`

### 6. Navigation
- **Back Button**: Returns to previous screen
- **Forgot Password**: Navigates to `ChangeForgottenPassword`
- **Successful Login**: Navigates to `selectionScreen`

### 7. Time-Based Gradient (`_getTimeBasedGradient`)
Dynamically changes background based on current hour (same as IntroductionScreen).

## Dependencies

- `package:flutter/material.dart` - Core Flutter widgets
- `package:flutter/services.dart` - System UI configuration
- `package:connectivity_plus/connectivity_plus.dart` - Network connectivity
- `package:flutter_svg/flutter_svg.dart` - SVG asset rendering
- `package:supabase_flutter/supabase_flutter.dart` - Supabase authentication
- `package:pasada_passenger_app/services/authService.dart` - Custom auth service
- `package:pasada_passenger_app/utils/toast_utils.dart` - Toast notifications
- `package:pasada_passenger_app/screens/forgotPasswordScreen.dart` - Forgot password screen
- `package:pasada_passenger_app/screens/selectionScreen.dart` - Selection screen

## Route Names

| Route | Screen |
|-------|--------|
| `loginAccount` | Login screen |
| `ChangeForgottenPassword` | Forgot password screen |
| `selectionScreen` | Main selection screen (after login) |
