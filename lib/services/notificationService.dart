import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pasada_passenger_app/functions/notification_preferences.dart';
import 'package:pasada_passenger_app/screens/selectionScreen.dart';
import 'package:pasada_passenger_app/services/encryptionService.dart';
import 'package:pasada_passenger_app/widgets/responsive_dialogs.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NotificationService {
  static final FlutterLocalNotificationsPlugin
      _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;

  // Serialization primitives
  static Completer<void>? _initCompleter;
  static Completer<void>? _permissionRequestCompleter;
  static final Queue<Future<void> Function()> _notificationQueue = Queue();
  static bool _isProcessingQueue = false;

  static const int rideProgressNotificationId = 1;

  static Future<void> initialize() async {
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();
    try {
      await _requestPermissions();

      // Initialize local notifications
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      final InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('Notification clicked with payload: ${response.payload}');
          _handleNotificationTap();
        },
      );

      // Create Android notification channel for ride progress updates
      if (Platform.isAndroid) {
        final androidImpl = _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          const AndroidNotificationChannel rideProgressChannel =
              AndroidNotificationChannel(
            'ride_progress_channel',
            'Ride Progress',
            description: 'Shows driver progress towards drop-off',
            importance: Importance.defaultImportance,
          );
          await androidImpl.createNotificationChannel(rideProgressChannel);
        }
      }

      // Set up FCM handlers
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);

      // Get FCM token and save it - but only if Supabase is initialized
      try {
        final String? fcmToken = await _firebaseMessaging.getToken();
        if (fcmToken != null) {
          // quiet
          // Only save token if Supabase is initialized
          await saveTokenToDatabase(fcmToken);
        }

        // Set up token refresh listener
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          // quiet
          // We'll try to save the token, but it will only work if Supabase is initialized
          saveTokenToDatabase(newToken);
        });
      } catch (e) {
        // quiet
      }
    } catch (e) {
      // quiet
    } finally {
      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter!.complete();
      }
    }
  }

  /// Initialize notifications without prompting for permissions.
  /// Use this during app startup to avoid blocking resource loading UI.
  static Future<void> initializeWithoutPrompt() async {
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();
    try {
      // Initialize local notifications only, skip permissions
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      final InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // quiet
          _handleNotificationTap();
        },
      );

      if (Platform.isAndroid) {
        final androidImpl = _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          const AndroidNotificationChannel rideProgressChannel =
              AndroidNotificationChannel(
            'ride_progress_channel',
            'Ride Progress',
            description: 'Shows driver progress towards drop-off',
            importance: Importance.defaultImportance,
          );
          await androidImpl.createNotificationChannel(rideProgressChannel);
        }
      }

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);

      try {
        final String? fcmToken = await _firebaseMessaging.getToken();
        if (fcmToken != null) {
          await saveTokenToDatabase(fcmToken);
        }
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          saveTokenToDatabase(newToken);
        });
      } catch (e) {
        // quiet
      }
    } catch (e) {
      // quiet
    } finally {
      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter!.complete();
      }
    }
  }

  /// Public method to request permissions later in the flow.
  static Future<void> requestPermissionsIfNeeded() async {
    await _requestPermissions();
  }

  /// Show app-styled pre-prompt before asking the OS for notification permission
  static Future<void> requestPermissionsWithPrePrompt(
      BuildContext context) async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ResponsiveDialog(
        title: 'Enable notifications?',
        contentPadding: const EdgeInsets.all(24),
        content: Text(
          'Stay updated with ride confirmations, driver location, and arrival notifications. You can change this anytime in Settings.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'Inter',
            color:
                isDarkMode ? const Color(0xFFDEDEDE) : const Color(0xFF1E1E1E),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFF00CC58), width: 3),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
              minimumSize: const Size(150, 40),
              backgroundColor: Colors.transparent,
              foregroundColor: isDarkMode
                  ? const Color(0xFFF5F5F5)
                  : const Color(0xFF121212),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Not now',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
                fontSize: 15,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
              minimumSize: const Size(150, 40),
              backgroundColor: const Color(0xFF00CC58),
              foregroundColor: const Color(0xFFF5F5F5),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Allow',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );

    if (proceed == true) {
      await _requestPermissions();
    }
  }

  // This method can be called after Supabase is fully initialized
  static Future<void> saveTokenAfterInit() async {
    try {
      final String? fcmToken = await _firebaseMessaging.getToken();
      if (fcmToken != null) {
        await saveTokenToDatabase(fcmToken);
      }
    } catch (e) {
      debugPrint('Error saving token after init: $e');
    }
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // quiet

    if (message.notification != null) {
      await showNotification(
        title: message.notification?.title ?? 'Pasada',
        body: message.notification?.body ?? 'You have a new notification',
      );
    }
  }

  static Future<void> _handleBackgroundMessageTap(RemoteMessage message) async {
    // quiet
    _handleNotificationTap();
  }

  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    _notificationQueue.add(() async {
      await _showNotificationInternal(
          title: title, body: body, payload: payload);
    });
    if (!_isProcessingQueue) {
      _processNotificationQueue();
    }
  }

  static Future<void> _showNotificationInternal({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final bool notificationsEnabled =
          await NotificationPreference.getNotificationStatus();
      if (!notificationsEnabled) return;

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'pasada_notifications',
        'Pasada Notifications',
        channelDescription: 'Notifications for Pasada',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.service,
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _flutterLocalNotificationsPlugin.show(
        id: 0,
        title: title,
        body: body,
        notificationDetails: platformChannelSpecifics,
        payload: payload,
      );
    } catch (e) {
      // quiet
    }
  }

  static Future<void> _processNotificationQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    try {
      while (_notificationQueue.isNotEmpty) {
        final task = _notificationQueue.removeFirst();
        await task();
        await Future.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  static void _handleNotificationTap() {
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const selectionScreen()),
        (route) => false,
      );
    }
  }

  // Send booking availability notification via FCM
  static Future<void> showAvailabilityNotification() async {
    try {
      // Check if notifications are enabled before showing
      final bool notificationsEnabled =
          await NotificationPreference.getNotificationStatus();
      if (!notificationsEnabled) return;

      // Get current user
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        // quiet
        await showNotification(
          title: 'Pasada',
          body: 'You can now book a ride!',
        );
        return;
      }

      try {
        // Get user's display name, then decrypt it
        final userData = await Supabase.instance.client
            .from('passenger')
            .select('display_name')
            .eq('id', user.id)
            .single();

        String userName = userData['display_name'] ?? 'user';
        try {
          final encryptionService = EncryptionService();
          await encryptionService.initialize();
          userName = await encryptionService.decryptUserData(userName);
        } catch (_) {}

        // For local notification fallback
        await showNotification(
          title: 'Pasada',
          body: 'Hello $userName, pwedeng-pwede ka na magbook, boss!',
        );

        // The actual FCM notification will be sent from the server
        // This is just a local fallback
      } catch (e) {
        // quiet
        await showNotification(
          title: 'Pasada',
          body: 'You can now book a ride!',
        );
      }
    } catch (e) {
      // quiet
    }
  }

  static Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id: id);
  }

  static Future<bool> checkPermissions() async {
    final bool? permissionGranted = await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();

    return permissionGranted ?? false;
  }

  static Future<void> _requestPermissions() async {
    if (_permissionRequestCompleter != null &&
        !_permissionRequestCompleter!.isCompleted) {
      return _permissionRequestCompleter!.future;
    }
    _permissionRequestCompleter = Completer<void>();
    try {
      // Request permission for FCM
      final NotificationSettings settings =
          await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('FCM permission status: ${settings.authorizationStatus}');

      // Request permission for local notifications
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        // On Android 13+, users can block notifications at OS level. Verify and fallback to settings.
        final bool notificationsEnabled =
            (await androidImplementation.areNotificationsEnabled()) ?? false;
        if (!notificationsEnabled) {
          // Try requesting via permission_handler for robustness
          final status = await Permission.notification.request();
          if (!status.isGranted) {
            debugPrint(
                'Notifications disabled; prompting to open app settings');
            await openAppSettings();
          }
        }
      }
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
    } finally {
      if (!(_permissionRequestCompleter?.isCompleted ?? true)) {
        _permissionRequestCompleter!.complete();
      }
    }
  }

  /// Call this from UI when a notification action fails due to disabled perms
  static Future<void> promptOpenSettingsIfDisabled(BuildContext context) async {
    bool enabled = await checkPermissions();
    if (enabled) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable notifications'),
        content: const Text(
          'Notifications are currently disabled. Enable them in system settings to receive updates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Save FCM token to your backend (Supabase in this case)
  static Future<void> saveTokenToDatabase(String token) async {
    try {
      bool isSupabaseInitialized = false;
      try {
        final _ = Supabase.instance.client;
        isSupabaseInitialized = true;
      } catch (e) {
        isSupabaseInitialized = false;
      }

      if (!isSupabaseInitialized) {
        // quiet
        return;
      }

      // Get current user ID from Supabase
      final user = Supabase.instance.client.auth.currentUser;

      // Get device info and encrypt it
      final rawDeviceInfo =
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      final deviceInfo = BCrypt.hashpw(rawDeviceInfo, BCrypt.gensalt());

      if (user != null) {
        try {
          await Supabase.instance.client.rpc(
            'save_fcm_token',
            params: {
              'p_token': token,
              'p_device_info': deviceInfo,
            },
          );
          // quiet
        } catch (e) {
          if (e.toString().contains('auth') ||
              e.toString().contains('Not initialized')) {
            // quiet
            return;
          }
          // quiet
        }
      } else {
        // quiet
      }
    } catch (e) {
      // quiet
    }
  }

  /// Shows an ongoing ride progress notification with a progress bar.
  static Future<void> showRideProgressNotification({
    required int progress,
    required int maxProgress,
    String title = 'Arriving',
  }) async {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'ride_progress_channel',
      'Ride Progress',
      channelDescription: 'Shows driver progress towards drop-off',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(
        '$progress% to drop-off',
        contentTitle: title,
      ),
    );
    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );
    await _flutterLocalNotificationsPlugin.show(
      id: rideProgressNotificationId,
      title: title,
      body: '$progress% to drop-off',
      notificationDetails: platformDetails,
    );
  }

  /// Cancels the ride progress notification.
  static Future<void> cancelRideProgressNotification() async {
    await _flutterLocalNotificationsPlugin.cancel(
        id: rideProgressNotificationId);
  }

  /// Gets a random dialogue message when a driver is found
  static String getRandomDriverFoundMessage() {
    final messages = [
      'May driver ka na, boss! Punta ka na sa pick-up location.',
      'Yown, nakahanap na rin ng driver sa wakas!',
      'Ayan, may driver ka na raw po. Punta na agad sa pick-up location!',
    ];
    final random = Random();
    return messages[random.nextInt(messages.length)];
  }

  /// Gets a random dialogue message when no driver is found
  static String getRandomNoDriverMessage() {
    final messages = [
      'Pasensiya na boss, wala talagang mahanap e.',
      'Palya pre, try mo ulit baka makahanap pa.',
      'Wala talaga, boss. Sorry huhu.',
    ];
    final random = Random();
    return messages[random.nextInt(messages.length)];
  }

  /// Shows a notification with random driver found message
  static Future<void> showDriverFoundNotification() async {
    final message = getRandomDriverFoundMessage();
    await showNotification(
      title: 'Driver Found!',
      body: message,
    );
  }

  /// Shows a notification with random no driver message
  static Future<void> showNoDriverNotification() async {
    final message = getRandomNoDriverMessage();
    await showNotification(
      title: 'No Driver Available',
      body: message,
    );
  }
}
