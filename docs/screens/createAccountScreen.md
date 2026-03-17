# CreateAccountScreen Documentation

## Overview

The `CreateAccountScreen` is the first step in the account creation flow for new users. It collects the user's email and password, validates the input, and then navigates to the credentials screen for additional information. The screen also supports Google sign-up as an alternative method.

## Location

`lib/authentication/createAccount.dart`

## Widgets Used

### 1. Scaffold
The root widget with `resizeToAvoidBottomInset` enabled for keyboard handling.

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
- **Header**: "Create Account" - 28-32px, bold, white
- **Subtitle**: "Yun o? Sign up ka na para makapagbook ka naman." - 14-16px, light gray
- **Labels**: "Email Address", "Password", "Confirm Password" - 14-15px, bold, white

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
- Suffix icon: Visibility toggle
- Same styling as email input

### 9. TextField (Confirm Password Input)
- Placeholder: "Confirm your password"
- Prefix icon: `Icons.lock_outlined`
- Suffix icon: Visibility toggle
- Same styling as other inputs

### 10. ElevatedButton (Continue)
- Background: Green (`#00CC58`)
- Full width with 50-56px height (responsive)
- 14px border radius
- Loading state: CircularProgressIndicator
- Text: "Continue" - 15-17px, bold, white

### 11. ElevatedButton (Continue with Google)
- Background: Transparent white (12% opacity)
- White border (30% opacity, 1.5px width)
- Full width with 50-56px height (responsive)
- 14px border radius
- Loading state: CircularProgressIndicator
- Icon: Google SVG icon
- Text: "Continue with Google"

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
import 'package:pasada_passenger_app/screens/selectionScreen.dart';
import 'package:pasada_passenger_app/services/authService.dart';
import 'package:pasada_passenger_app/utils/toast_utils.dart';

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

bool isGoogleLoading = false;

class _CreateAccountPageState extends State<CreateAccountPage> {
  @override
  Widget build(BuildContext context) {
    return const CAPage(title: 'Pasada');
  }
}

class CAPage extends StatefulWidget {
  const CAPage({super.key, required this.title});

  final String title;

  @override
  State<CAPage> createState() => CreateAccountScreen();
}

class CreateAccountScreen extends State<CAPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  final AuthService authService = AuthService();
  final session = supabase.auth.currentSession;

  bool isPasswordVisible = false;
  String errorMessage = '';
  bool isLoading = false;

  final Connectivity connectivity = Connectivity();

  // ... (rest of the implementation)
}
```

## How It Works

### 1. Initialization (`initState`)
- Configures status bar style (white icons)
- Calculates responsive values based on screen size

### 2. Email/Password Sign Up (`SigningUp`)
1. Validates that all fields are filled
2. Validates email format using regex
3. Validates password is at least 8 characters
4. Validates password and confirm password match
5. Checks network connectivity
6. On validation success: Navigates to `cred` route with email and password as arguments

### 3. Validation Rules
- **Email**: Must not be empty and must match email regex pattern
- **Password**: Must be at least 8 characters
- **Confirm Password**: Must match password field
- **Network**: Must have active internet connection

### 4. Google Sign-Up (`buildSignUpGoogle`)
1. Checks network connectivity first
2. Shows "Signing up with Google..." info toast
3. Calls `authService.signInWithGoogle()`
4. On success: Shows success toast and navigates to selectionScreen with pushReplacement
5. On cancellation/failure: Shows appropriate error message
6. Loading state prevents multiple clicks

### 5. Password Visibility Toggle
- Single toggle controls both password fields
- Uses `Icons.visibility_outlined` and `Icons.visibility_off_outlined`

### 6. Navigation
- **Back Button**: Returns to previous screen
- **Continue Button**: Navigates to `cred` route with email/password arguments
- **Continue with Google**: Navigates to selectionScreen (replaces current route)
- **Successful Sign-Up**: Navigates to `selectionScreen`

### 7. Time-Based Gradient (`_getTimeBasedGradient`)
Dynamically changes background based on current hour (same as IntroductionScreen).

### 8. Responsive Design
- Uses `MediaQuery` to calculate screen dimensions
- Adjusts padding, font sizes, and button heights based on screen size
- `isSmallScreen` flag: screenHeight < 600 || screenWidth < 400

## Dependencies

- `package:flutter/material.dart` - Core Flutter widgets
- `package:flutter/services.dart` - System UI configuration
- `package:connectivity_plus/connectivity_plus.dart` - Network connectivity
- `package:flutter_svg/flutter_svg.dart` - SVG asset rendering
- `package:pasada_passenger_app/main.dart` - Main app with Supabase session
- `package:pasada_passenger_app/screens/selectionScreen.dart` - Selection screen
- `package:pasada_passenger_app/services/authService.dart` - Custom auth service
- `package:pasada_passenger_app/utils/toast_utils.dart` - Toast notifications

## Route Names

| Route | Screen |
|-------|--------|
| `createAccount` | Create account screen (this screen) |
| `cred` | Credentials screen (createAccountCred) |
| `selectionScreen` | Main selection screen (after Google sign-up) |

## Arguments Passed

When navigating to the `cred` route, the following arguments are passed:
```dart
{
  'email': email,      // User's email address
  'password': password // User's password
}
```
