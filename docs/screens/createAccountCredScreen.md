# CreateAccountCredScreen Documentation

## Overview

The `CreateAccountCredScreen` is the second step in the account creation flow. It collects the user's full name and contact number, validates the input, checks for phone number availability, and then navigates to OTP verification. It also includes a terms and conditions acceptance checkbox with links to view them.

## Location

`lib/authentication/createAccountCred.dart`

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
- **Header**: "Almost There!" - 28-32px, bold, white
- **Subtitle**: "Kaunti na lang, bossing. Hehehe." - 14-16px, light gray
- **Labels**: "Full Name", "Contact Number" - 14-15px, bold, white

### 7. TextField (Full Name Input)
- Placeholder: "Enter your full name"
- Prefix icon: `Icons.person_outline`
- Background: White with 12% opacity
- Border: 1.5px white with 30% opacity (default), 2px green (focused)
- Border radius: 14px
- Cursor color: Green (`#00CC58`)

### 8. TextField (Contact Number Input)
- Placeholder: "9123456789"
- Keyboard type: `TextInputType.phone`
- Input formatters: Digits only, max 10 characters
- Prefix: Philippine flag SVG + "+63" country code
- Background: White with 12% opacity
- Border: Same styling as name input

### 9. SvgPicture (Philippine Flag)
- Asset: `assets/svg/phFlag.svg`
- Size: 20-22px (responsive)
- Displayed with "+63" country code

### 10. Row (Terms Checkbox)
- **Checkbox**: 
  - Scale: 1.0-1.15 (responsive)
  - Check color: White
  - Active color: Green (`#00CC58`)
  - Border: White with 50% opacity, 1.5px
  - Shape: Rounded rectangle (4px radius)
- **RichText**:
  - Default text: "I agree to Pasada's "
  - "Terms and Conditions" - Green, underlined, clickable
  - " and " text
  - "Privacy Policy" - Green, underlined, clickable

### 11. ElevatedButton (Create Account)
- Background: Green (`#00CC58`)
- Full width with 50-56px height (responsive)
- 14px border radius
- Loading state: CircularProgressIndicator
- Text: "Create Account" - 15-17px, bold, white
- Disabled when terms not checked

## Sample Code

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pasada_passenger_app/authentication/otpVerificationScreen.dart';
import 'package:pasada_passenger_app/screens/privacyPolicyScreen.dart';
import 'package:pasada_passenger_app/screens/termsAndConditionsScreen.dart';
import 'package:pasada_passenger_app/services/phoneValidationService.dart';
import 'package:pasada_passenger_app/utils/toast_utils.dart';

class CreateAccountCredPage extends StatefulWidget {
  final String email;
  final String title;

  const CreateAccountCredPage(
      {super.key, required this.title, required this.email});

  @override
  State<CreateAccountCredPage> createState() => _CreateAccountCredPageState();
}

class _CreateAccountCredPageState extends State<CreateAccountCredPage> {
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final contactController = TextEditingController();
  bool isChecked = false;
  bool isLoading = false;

  LinearGradient _getTimeBasedGradient() {
    // Same gradient logic as other screens
  }

  // ... (rest of the implementation)
}
```

## How It Works

### 1. Initialization
- Configures status bar style (white icons)
- Calculates responsive values based on screen size
- Receives email from previous screen via widget property

### 2. Input Validation (`handleSignUp`)

#### Terms and Conditions
- Checks if checkbox is checked
- Shows warning if not checked

#### Display Name Validation
- Must not be empty
- Must be at least 2 characters

#### Phone Number Validation
- Must be exactly 10 digits
- Must start with 9 (Philippine mobile number format)
- Uses regex: `^\d{10}$`

### 3. Phone Number Availability Check
1. Checks network connectivity
2. Calls `PhoneValidationService.isPhoneNumberAvailable(contactNumber)`
3. If number already registered: Shows error and stops
4. If available: Proceeds to OTP verification

### 4. Navigation to OTP
On successful validation:
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => OTPVerificationScreen(
      phoneNumber: contactNumber,    // +63XXXXXXXXXX
      email: email,                  // From widget property
      password: password,            // From route arguments
      displayName: displayName,      // From text field
    ),
  ),
);
```

### 5. Terms and Conditions Links
- **Terms and Conditions**: Navigates to `TermsAndConditionsScreen`
- **Privacy Policy**: Navigates to `PrivacyPolicyScreen`
- Both use `TapGestureRecognizer` for click handling

### 6. Password Visibility
- Arguments passed from previous screen via `ModalRoute.of(context)!.settings.arguments`
- Contains: `{'email': email, 'password': password}`

### 7. Contact Number Formatting
- Input: 10 digits (e.g., "9123456789")
- Stored as: "+63" + digits (e.g., "+639123456789")

### 8. Time-Based Gradient (`_getTimeBasedGradient`)
Dynamically changes background based on current hour (same as IntroductionScreen).

### 9. Responsive Design
- Uses `MediaQuery` to calculate screen dimensions
- Adjusts padding, font sizes, and button heights based on screen size
- `isSmallScreen` flag: screenHeight < 600 || screenWidth < 400

## Dependencies

- `package:flutter/material.dart` - Core Flutter widgets
- `package:flutter/services.dart` - System UI configuration
- `package:connectivity_plus/connectivity_plus.dart` - Network connectivity
- `package:flutter_svg/flutter_svg.dart` - SVG asset rendering
- `package:pasada_passenger_app/authentication/otpVerificationScreen.dart` - OTP verification
- `package:pasada_passenger_app/screens/privacyPolicyScreen.dart` - Privacy policy
- `package:pasada_passenger_app/screens/termsAndConditionsScreen.dart` - Terms and conditions
- `package:pasada_passenger_app/services/phoneValidationService.dart` - Phone validation
- `package:pasada_passenger_app/utils/toast_utils.dart` - Toast notifications

## Arguments Received

From the previous `createAccount` screen:
```dart
{
  'email': email,      // User's email address
  'password': password // User's password
}
```

## Arguments Passed to OTP Screen

```dart
{
  'phoneNumber': contactNumber,  // +63XXXXXXXXXX (with country code)
  'email': email,                // From widget property
  'password': password,          // From route arguments
  'displayName': displayName     // From firstNameController
}
```

## Route Names

| Route | Screen |
|-------|--------|
| `cred` | Create account credentials screen (this screen) |
| `TermsAndConditionsScreen` | Terms and conditions viewing |
| `PrivacyPolicyScreen` | Privacy policy viewing |
| `OTPVerificationScreen` | OTP verification (after validation) |

## Validation Rules Summary

| Field | Rules |
|-------|-------|
| Full Name | Not empty, min 2 characters |
| Contact Number | Exactly 10 digits, starts with 9 |
| Terms Checkbox | Must be checked |
| Network | Must have active connection |
| Phone Availability | Must not be already registered |
