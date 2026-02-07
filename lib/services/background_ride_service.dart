import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundRideService {
  static const String _channelId = 'ride_tracking_service';
  static const String _channelName = 'Ride Tracking Service';
  static const String _channelDescription =
      'Keeps the app running in background during active rides';
  static const int _notificationId = 9999;

  static const MethodChannel _platform =
      MethodChannel('background_ride_service');
  static ReceivePort? _receivePort;
  static Isolate? _isolate;
  static bool _isServiceRunning = false;

  /// Initialize the background service
  static Future<void> initialize() async {
    try {
      // Set up method channel for communication with native code
      _platform.setMethodCallHandler(_handleMethodCall);

      // Create notification channel for the service
      await _createNotificationChannel();

      debugPrint('BackgroundRideService initialized');
    } catch (e) {
      debugPrint('Error initializing BackgroundRideService: $e');
    }
  }

  /// Start the background service for ride tracking
  static Future<void> startService({
    required int bookingId,
    required String rideStatus,
    required String pickupAddress,
    required String dropoffAddress,
  }) async {
    if (_isServiceRunning) {
      debugPrint('Background service is already running');
      return;
    }

    try {
      // Request necessary permissions
      await _requestPermissions();

      // Start the background isolate
      await _startBackgroundIsolate();

      // Start native background service
      await _platform.invokeMethod('startBackgroundService');

      // Show persistent notification
      await _showServiceNotification(
        bookingId: bookingId,
        rideStatus: rideStatus,
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
      );

      // Start location tracking in background
      await _startBackgroundLocationTracking(bookingId);

      // Save ride data for persistence
      await _saveRideData(
        bookingId: bookingId,
        rideStatus: rideStatus,
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
      );

      _isServiceRunning = true;
      debugPrint('Background ride service started for booking $bookingId');
    } catch (e) {
      debugPrint('Error starting background service: $e');
      rethrow;
    }
  }

  /// Stop the background service
  static Future<void> stopService() async {
    if (!_isServiceRunning) {
      debugPrint('Background service is not running');
      return;
    }

    try {
      // Stop location tracking
      await _stopBackgroundLocationTracking();

      // Stop native background service
      await _platform.invokeMethod('stopBackgroundService');

      // Cancel the persistent notification
      await _cancelServiceNotification();

      // Stop the background isolate
      await _stopBackgroundIsolate();

      // Clear saved ride data
      await _clearRideData();

      _isServiceRunning = false;
      debugPrint('Background ride service stopped');
    } catch (e) {
      debugPrint('Error stopping background service: $e');
    }
  }

  /// Update the service notification with new ride status
  static Future<void> updateServiceNotification({
    required String rideStatus,
    String? driverName,
    String? estimatedArrival,
    String? dropoffAddress,
  }) async {
    if (!_isServiceRunning) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final bookingId = prefs.getInt('activeBookingId');
      final pickupAddress =
          prefs.getString('pickupAddress') ?? 'Pickup location';
      final dropoffAddress =
          prefs.getString('dropoffAddress') ?? 'Drop-off location';

      await _showServiceNotification(
        bookingId: bookingId ?? 0,
        rideStatus: rideStatus,
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
        driverName: driverName,
        estimatedArrival: estimatedArrival,
      );

      // Update native service notification with structured data
      await _platform.invokeMethod('updateServiceNotification', {
        'title': 'Pasada',
        'content': 'Ride in progress',
        'eta': estimatedArrival,
        'destination': dropoffAddress,
        'progress': _getProgressForStatus(rideStatus),
      });
    } catch (e) {
      debugPrint('Error updating service notification: $e');
    }
  }

  /// Check if the service is currently running
  static bool get isServiceRunning => _isServiceRunning;

  /// Check if there's an active ride that should keep the service running
  static Future<bool> hasActiveRide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookingId = prefs.getInt('activeBookingId');
      final rideStatus = prefs.getString('rideStatus');

      return bookingId != null &&
          rideStatus != null &&
          (rideStatus == 'accepted' || rideStatus == 'ongoing');
    } catch (e) {
      debugPrint('Error checking active ride: $e');
      return false;
    }
  }

  /// Restore background service if there's an active ride
  static Future<void> restoreServiceIfNeeded() async {
    try {
      if (await hasActiveRide()) {
        final prefs = await SharedPreferences.getInstance();
        final bookingId = prefs.getInt('activeBookingId') ?? 0;
        final rideStatus = prefs.getString('rideStatus') ?? 'accepted';
        final pickupAddress =
            prefs.getString('pickupAddress') ?? 'Pickup location';
        final dropoffAddress =
            prefs.getString('dropoffAddress') ?? 'Drop-off location';

        await startService(
          bookingId: bookingId,
          rideStatus: rideStatus,
          pickupAddress: pickupAddress,
          dropoffAddress: dropoffAddress,
        );

        debugPrint('Background service restored for active ride $bookingId');
      }
    } catch (e) {
      debugPrint('Error restoring background service: $e');
    }
  }

  /// Create notification channel for the service
  static Future<void> _createNotificationChannel() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.low,
      showBadge: false,
      enableVibration: false,
    );

    final androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(channel);
    }
  }

  /// Show persistent notification for the service
  static Future<void> _showServiceNotification({
    required int bookingId,
    required String rideStatus,
    required String pickupAddress,
    required String dropoffAddress,
    String? driverName,
    String? estimatedArrival,
  }) async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    String title = 'Pasada - Ride in Progress';
    String body = 'Your ride is $rideStatus';

    if (driverName != null) {
      body += ' • Driver: $driverName';
    }
    if (estimatedArrival != null) {
      body += ' • ETA: $estimatedArrival';
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      showWhen: false,
      ongoing: true,
      autoCancel: false,
      enableVibration: false,
      category: AndroidNotificationCategory.service,
      visibility: NotificationVisibility.private,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  /// Cancel the service notification
  static Future<void> _cancelServiceNotification() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin.cancel(id: _notificationId);
  }

  /// Request necessary permissions
  static Future<void> _requestPermissions() async {
    // Request location permissions
    final locationStatus = await perm.Permission.locationWhenInUse.request();
    if (locationStatus != perm.PermissionStatus.granted) {
      throw Exception('Location permission is required for ride tracking');
    }

    // Request background location permission for Android
    if (await perm.Permission.locationAlways.isDenied) {
      await perm.Permission.locationAlways.request();
    }

    // Request notification permission
    final notificationStatus = await perm.Permission.notification.request();
    if (notificationStatus != perm.PermissionStatus.granted) {
      debugPrint(
          'Notification permission denied - service notification may not work');
    }
  }

  /// Start background isolate for location tracking
  static Future<void> _startBackgroundIsolate() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
        _backgroundIsolateEntryPoint, _receivePort!.sendPort);

    _receivePort!.listen((dynamic data) {
      debugPrint('Background isolate message: $data');
    });
  }

  /// Stop background isolate
  static Future<void> _stopBackgroundIsolate() async {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _receivePort = null;
  }

  /// Background isolate entry point
  static void _backgroundIsolateEntryPoint(SendPort sendPort) {
    // This isolate will handle background location tracking
    // and other background tasks
    debugPrint('Background isolate started');
  }

  /// Start background location tracking
  static Future<void> _startBackgroundLocationTracking(int bookingId) async {
    try {
      // Warm up GPS and keep stream alive in background with balanced accuracy
      final location = Location();
      try {
        await location.enableBackgroundMode(enable: true);
      } catch (_) {}
      try {
        await location.changeSettings(
          accuracy: LocationAccuracy.balanced,
          interval: 5000,
        );
      } catch (_) {}

      // Trigger a quick initial get to warm GPS with short timeout
      try {
        await location.getLocation().timeout(const Duration(seconds: 5));
      } catch (_) {}

      // Note: Actual upload to server should be implemented via a repository/service
      debugPrint('Background location tracking started for booking $bookingId');
    } catch (e) {
      debugPrint('Error starting background location tracking: $e');
    }
  }

  /// Stop background location tracking
  static Future<void> _stopBackgroundLocationTracking() async {
    try {
      debugPrint('Background location tracking stopped');
    } catch (e) {
      debugPrint('Error stopping background location tracking: $e');
    }
  }

  /// Handle method calls from native code
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLocationUpdate':
        // Handle location updates from native code
        debugPrint('Location update received: ${call.arguments}');
        break;
      case 'onServiceDestroyed':
        // Handle service destruction
        _isServiceRunning = false;
        debugPrint('Background service destroyed');
        break;
      default:
        debugPrint('Unknown method call: ${call.method}');
    }
  }

  /// Save ride data to SharedPreferences for persistence
  static Future<void> _saveRideData({
    required int bookingId,
    required String rideStatus,
    required String pickupAddress,
    required String dropoffAddress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('activeBookingId', bookingId);
    await prefs.setString('rideStatus', rideStatus);
    await prefs.setString('pickupAddress', pickupAddress);
    await prefs.setString('dropoffAddress', dropoffAddress);
    await prefs.setBool('isBackgroundServiceRunning', true);
  }

  /// Clear ride data from SharedPreferences
  static Future<void> _clearRideData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('activeBookingId');
    await prefs.remove('rideStatus');
    await prefs.remove('pickupAddress');
    await prefs.remove('dropoffAddress');
    await prefs.setBool('isBackgroundServiceRunning', false);
  }

  /// Get progress percentage based on ride status
  static int _getProgressForStatus(String rideStatus) {
    switch (rideStatus) {
      case 'accepted':
        return 25; // Driver found, starting journey
      case 'ongoing':
        return 60; // Ride in progress
      case 'completed':
        return 100; // Ride completed
      default:
        return 0;
    }
  }

  /// Test method to show custom notification (for debugging)
  static Future<void> testCustomNotification() async {
    try {
      await _platform.invokeMethod('updateServiceNotification', {
        'title': 'Pasada',
        'content': 'Ride in progress',
        'eta': '05:17 AM',
        'destination': 'Dra Evelyn B Reyes Clinic',
        'progress': 60,
      });
      debugPrint('Test custom notification sent');
    } catch (e) {
      debugPrint('Error testing custom notification: $e');
    }
  }
}
