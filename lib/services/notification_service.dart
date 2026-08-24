// lib/services/notification_service.dart
//
// Handles Firebase Cloud Messaging + flutter_callkit_incoming v3.x.
// Covers foreground, background, and terminated (killed) app states.
// ─────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
// ─── TOP-LEVEL BACKGROUND HANDLER ─────────────────────────────────────────
//
// MUST be a top-level function (outside any class).
// Called by Firebase in a separate isolate when app is background/terminated.
//
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[BG Handler] data: ${message.data}');
  final data = message.data;
  final type = data['type'] ?? '';

  if (type == 'call') {
    await _showCallkitIncoming(data);
  } else if (type == 'message') {
    // Handled natively by FCM notification payload in background/killed state.
  }
}

// ─── CALLKIT HELPER (top-level, callable from background isolate) ──────────

Future<void> _showCallkitIncoming(Map<String, dynamic> data) async {
  final uuid         = data['callUuid']    ?? 'uuid-${DateTime.now().millisecondsSinceEpoch}';
  final callerName   = data['callerName']  ?? 'Unknown Caller';
  final callRoomId   = data['callRoomId']  ?? '';

  final params = CallKitParams(
    id: uuid,
    nameCaller: callerName,
    appName: 'SajniRe',
    handle: 'SajniRe Audio Call',
    type: 0,          // 0 = audio call
    duration: 30000,  // auto-dismiss after 30s
    // Pass call info through extra so we can navigate on Accept
    extra: <String, dynamic>{
      'callRoomId': callRoomId,
      'callerName': callerName,
    },
    headers: <String, dynamic>{'platform': 'android'},
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      isShowCallID: false,
      ringtonePath: 'system_ringtone_default', // explicitly request default system ringtone
      backgroundColor: '#1976D2',
      actionColor: '#4CAF50',
      textColor: '#ffffff',
      isShowFullLockedScreen: true,
      isImportant: true,
      isFullScreen: true,
    ),
    ios: const IOSParams(
      iconName: 'CallKitLogo',
      handleType: '',
      supportsVideo: false,
      maximumCallGroups: 2,
      maximumCallsPerCallGroup: 1,
      supportsDTMF: true,
      supportsHolding: true,
      supportsGrouping: false,
      supportsUngrouping: false,
      ringtonePath: 'system_ringtone_default',
      audioSessionMode: 'default',
      audioSessionActive: true,
      audioSessionPreferredSampleRate: 44100.0,
      audioSessionPreferredIOBufferDuration: 0.005,
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

// ─── NOTIFICATION SERVICE CLASS ───────────────────────────────────────────

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  /// Global NavigatorKey — set from main.dart.
  /// Used to push routes after accepting a call from the lock screen.
  static GlobalKey<NavigatorState>? navigatorKey;

  // ── INITIALIZE ──────────────────────────────────────────────────────────

  Future<void> initialize({required GlobalKey<NavigatorState> navKey}) async {
    navigatorKey = navKey;

    // 1. Register the top-level background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 2. Request notification permissions (Android 13+, iOS)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    // 2.5 Request System Alert Window (Display over other apps) and Notification permission via permission_handler
    try {
      if (Platform.isAndroid) {
         // This is critical for showing full screen incoming call and ringing like WhatsApp
         final status = await Permission.systemAlertWindow.status;
         if (!status.isGranted) {
           await Permission.systemAlertWindow.request();
         }
         await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('[Permission] Error requesting system alert window: $e');
    }

    // 3. iOS: don't show system banner for FCM — we use CallKit instead
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    // 4. Set up local notification channels
    await _initLocalNotifications();

    // 5. Foreground handler (app is open and visible)
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 6. Background tap handler (app was suspended but not killed)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // 7. Terminated state tap handler (app was completely killed)
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleMessageOpenedApp(initial);

    // 8. Listen to CallKit events (Accept / Decline from lock screen)
    _listenCallKitEvents();
  }

  // ── LOCAL NOTIFICATION SETUP ───────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          final data = jsonDecode(details.payload!) as Map<String, dynamic>;
          _routeFromNotification(data);
        }
      },
    );

    // Create Android channels
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'calls_channel',
        'Incoming Calls',
        description: 'Native incoming call notifications',
        importance: Importance.max,
        playSound: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'messages_channel',
        'Messages',
        description: 'Chat message notifications',
        importance: Importance.high,
        playSound: true,
      ),
    );
  }

  // ── FCM TOKEN MANAGEMENT ───────────────────────────────────────────────

  /// Call this after login to bind FCM token to the Firestore user document.
  ///
  /// [userId]     = lowercase nickname (experts) or mobile number (users)
  /// [collection] = 'experts' for female experts, 'users' for male callers
  Future<void> saveTokenForUser({
    required String userId,
    required String collection,
  }) async {
    try {
      final token = await _messaging.getToken();
      if (token == null || userId.isEmpty) return;

      await FirebaseFirestore.instance
          .collection(collection)
          .doc(userId)
          .set({'fcmToken': token}, SetOptions(merge: true));

      debugPrint('[FCM] Token saved → $collection/$userId');

      // Auto-refresh when token rotates
      _messaging.onTokenRefresh.listen((t) async {
        await FirebaseFirestore.instance
            .collection(collection)
            .doc(userId)
            .set({'fcmToken': t}, SetOptions(merge: true));
        debugPrint('[FCM] Token refreshed → $collection/$userId');
      });
    } catch (e) {
      debugPrint('[FCM] Error saving token: $e');
    }
  }

  // ── FOREGROUND HANDLER ────────────────────────────────────────────────

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM] Foreground: ${message.data}');
    final data = message.data;
    final type = data['type'] ?? '';

    if (type == 'call') {
      // Show native CallKit even when the app is open — consistent UX
      await _showCallkitIncoming(data);
    } else if (type == 'message') {
      await _showLocalNotification(data);
    }
  }

  Future<void> _showLocalNotification(Map<String, dynamic> data) async {
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: data['senderName'] ?? 'New Message',
      body: data['body'] ?? '',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'messages_channel',
          'Messages',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  // ── BACKGROUND TAP HANDLER ────────────────────────────────────────────

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] Notification tapped from background: ${message.data}');
    _routeFromNotification(message.data);
  }

  void _routeFromNotification(Map<String, dynamic> data) {
    // Call routing is handled via CallKit events (see _listenCallKitEvents).
    // Add chat routing here for 'message' type if needed:
    // if (data['type'] == 'message') navigatorKey?.currentState?.pushNamed('/chat', ...);
  }

  // ── CALLKIT EVENT LISTENER ────────────────────────────────────────────

  /// Listens to OS-level CallKit events.
  /// On Accept → navigates to ActiveCallPage.
  /// On Decline → marks call as 'ended' in Firestore.
  void _listenCallKitEvents() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      debugPrint('[CallKit] Event: ${event.eventName}');

      if (event is CallEventActionCallAccept) {
        // The UUID we passed as CallKitParams.id equals the Firestore callRoomId
        final callRoomId = event.id;
        debugPrint('[CallKit] Accepted: $callRoomId');

        // Navigate to active call screen
        // If app was killed, navigatorKey.currentState might be null briefly.
        // We poll for it to become ready before pushing.
        void pushRoute() {
          if (navigatorKey?.currentState != null) {
            navigatorKey!.currentState!.pushNamed(
              '/active-call',
              arguments: <String, dynamic>{
                'callRoomId': callRoomId,
                'callerName': 'Caller',
              },
            );
          } else {
            Future.delayed(const Duration(milliseconds: 200), pushRoute);
          }
        }
        pushRoute();
      } else if (event is CallEventActionCallDecline) {
        final callRoomId = event.id;
        debugPrint('[CallKit] Declined: $callRoomId');

        // Notify caller by updating Firestore call status
        if (callRoomId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(callRoomId)
              .update({'status': 'ended'}).catchError(
                  (e) => debugPrint('[CallKit] Firestore error: $e'));
        }
      } else if (event is CallEventActionCallTimeout) {
        debugPrint('[CallKit] Call timed out.');
        await FlutterCallkitIncoming.endAllCalls();
      }
    });
  }

  /// Dismiss all CallKit screens programmatically.
  /// Call when the expert goes offline to cancel any shown call screens.
  Future<void> endAllCallkitScreens() async {
    await FlutterCallkitIncoming.endAllCalls();
  }
}
