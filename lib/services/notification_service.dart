// lib/services/notification_service.dart
//
// Handles Firebase Cloud Messaging + flutter_callkit_incoming v3.x.
// Covers foreground, background, and terminated (killed) app states.
// ─────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../firebase_options.dart';
import 'call_service.dart';
import 'block_service.dart';

// ─── TOP-LEVEL BACKGROUND HANDLER ─────────────────────────────────────────
//
// MUST be a top-level function (outside any class).
// Called by Firebase in a separate isolate when app is background/terminated.
//
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
    } catch (e) {
      if (!e.toString().contains('duplicate-app')) {
        rethrow;
      }
    }
    debugPrint('[BG Handler] data: ${message.data}');
    final data = message.data;
    final type = data['type'] ?? '';

    if (type == 'call') {
      await _showCallkitIncoming(data);
    } else if (type == 'message') {
      final plugin = FlutterLocalNotificationsPlugin();
      const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
      const iosSettings = DarwinInitializationSettings();
      await plugin.initialize(
        settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
      );
      await showChatNotification(data);
    }
  } catch (e, stackTrace) {
    debugPrint('[BG Handler] ERROR: $e\n$stackTrace');
  }
}

// ─── LOCAL CHAT NOTIFICATION HELPER ──────────────────────────────────────────

Future<void> showChatNotification(Map<String, dynamic> data) async {
  final plugin = FlutterLocalNotificationsPlugin();
  
  ByteArrayAndroidBitmap? largeIcon;
  Uint8List? iconBytes;
  final avatarUrl = data['senderAvatar'] as String?;
  
  if (avatarUrl != null && avatarUrl.isNotEmpty) {
    try {
      final request = await HttpClient().getUrl(Uri.parse(avatarUrl));
      final response = await request.close();
      if (response.statusCode == 200) {
        iconBytes = await consolidateHttpClientResponseBytes(response);
        largeIcon = ByteArrayAndroidBitmap(iconBytes);
      }
    } catch (e) {
      debugPrint('[FCM] Error downloading avatar for notification: $e');
    }
  }

  // Fallback to static default avatar if no valid avatar was fetched
  if (iconBytes == null) {
    try {
      final receiverGender = data['receiverGender'] as String?;
      
      // If receiver is male, the message is FROM a female (use female avatar).
      // Otherwise, use male avatar.
      final assetPath = receiverGender == 'male' 
          ? 'assets/female_avatar_small.png' 
          : 'assets/male_avatar_small.png';
          
      final ByteData byteData = await rootBundle.load(assetPath);
      iconBytes = byteData.buffer.asUint8List();
      largeIcon = ByteArrayAndroidBitmap(iconBytes);
    } catch (e) {
      debugPrint('[FCM] Error loading default avatar asset: $e');
    }
  }

  // Use MessagingStyle for a chat-like premium look
  final person = Person(
    name: data['senderName'] ?? 'New Message',
    icon: iconBytes != null ? ByteArrayAndroidIcon(iconBytes) : null,
  );
  
  final styleInfo = MessagingStyleInformation(
    person,
    messages: [
      Message(data['body'] ?? '', DateTime.now(), person),
    ],
  );

  await plugin.show(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
    title: data['senderName'] ?? 'New Message',
    body: data['body'] ?? '',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'messages_channel',
        'Messages',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: styleInfo,
        largeIcon: largeIcon,
      ),
    ),
    payload: jsonEncode(data),
  );
}

// ─── CALLKIT HELPER (top-level, callable from background isolate) ──────────

Future<void> _showCallkitIncoming(Map<String, dynamic> data) async {
  debugPrint('[CallKit] _showCallkitIncoming triggered with data: $data');
  final uuid         = data['callRoomId']  ?? 'uuid-${DateTime.now().millisecondsSinceEpoch}';
  final callerName   = data['callerName']  ?? 'Unknown Caller';
  final callRoomId   = data['callRoomId']  ?? '';
  final callerId     = data['callerId']    ?? '';

  // 1. Check if caller is blocked locally before ringing
  if (callerId.isNotEmpty) {
    debugPrint('[CallKit] Checking if blocked: $callerId');
    try {
      bool isBlocked = await BlockService.instance.isUserBlockedAnywhereAsync(callerId);
      if (isBlocked) {
        debugPrint('[CallKit] Caller $callerId is blocked locally. Suppressing call.');
        return;
      }
    } catch(e) {
      debugPrint('[CallKit] Error checking block status: $e');
    }
  }

  // 2. Prevent "Ghost Ringing" without delaying the UI!
  // We immediately show the CallKit UI, but we also attach a listener.
  // If the RTDB connects and tells us the call is already ended/deleted, we kill the CallKit UI instantly.
  StreamSubscription? ghostCheckSub;
  if (callRoomId.isNotEmpty) {
    ghostCheckSub = FirebaseDatabase.instance.ref('calls/$callRoomId').onValue.listen((event) {
      if (!event.snapshot.exists || (event.snapshot.value as Map?)?['status'] == 'ended') {
        debugPrint('[CallKit] Ghost call detected (ended/deleted). Auto-canceling CallKit.');
        FlutterCallkitIncoming.endCall(uuid);
        FlutterRingtonePlayer().stop();
        ghostCheckSub?.cancel();
      }
    });
    // Auto cancel the subscription after 20 seconds to prevent memory leaks
    Future.delayed(const Duration(seconds: 20), () {
      ghostCheckSub?.cancel();
    });
  }

  debugPrint('[CallKit] Proceeding to ring...');
  NotificationService.lastCallerName = callerName;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('callerName_$callRoomId', callerName);
  await prefs.setString('callerId_$callRoomId', callerId);

  // Explicitly play the ringtone using flutter_ringtone_player
  FlutterRingtonePlayer().play(
    android: AndroidSounds.ringtone,
    ios: IosSounds.glass,
    looping: true,
    volume: 1.0,
    asAlarm: true,
  );

  final params = CallKitParams(
    id: uuid,
    nameCaller: callerName,
    appName: 'SajniRe',
    handle: 'calling ....',
    type: 0,          
    duration: 15000,  // auto-dismiss after 15s
    extra: <String, dynamic>{
      'callRoomId': callRoomId,
      'callerName': callerName,
    },
    headers: <String, dynamic>{'platform': 'android'},
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      isShowCallID: true,
      ringtonePath: '', // Handled manually
      backgroundColor: '#0A0A0A',
      actionColor: '#10B981',
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

  // Keep background isolate alive until call ends or times out
  final completer = Completer<void>();

  late StreamSubscription<CallEvent?> callkitEventSub;
  callkitEventSub = FlutterCallkitIncoming.onEvent.listen((event) {
    if (event is CallEventActionCallAccept ||
        event is CallEventActionCallDecline ||
        event is CallEventActionCallTimeout ||
        event is CallEventActionCallEnded) {
      FlutterRingtonePlayer().stop();
      if (!completer.isCompleted) completer.complete();
    }
  });

  StreamSubscription? rtdbSub;
  if (callRoomId.isNotEmpty) {
    rtdbSub = FirebaseDatabase.instance.ref('calls/$callRoomId').onValue.listen((event) {
      if (event.snapshot.value == null) {
        FlutterRingtonePlayer().stop();
        FlutterCallkitIncoming.endAllCalls();
        if (!completer.isCompleted) completer.complete();
      } else {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        if (data['status'] == 'ended' || data['status'] == 'rejected_blocked') {
          FlutterRingtonePlayer().stop();
          FlutterCallkitIncoming.endAllCalls();
          if (!completer.isCompleted) completer.complete();
        }
      }
    });
  }

  // Failsafe timer: maximum 16 seconds
  Timer(const Duration(seconds: 16), () {
    FlutterRingtonePlayer().stop();
    if (!completer.isCompleted) completer.complete();
  });

  await completer.future;
  
  callkitEventSub.cancel();
  rtdbSub?.cancel();
}

// ─── NOTIFICATION SERVICE CLASS ───────────────────────────────────────────

class NotificationService {
  static String? lastCallerName;
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

    // Permissions (like push notifications) should now be requested gracefully 
    // via PermissionHelper bottom sheet in the dashboard, NOT here.

    // 2.5 Request System Alert Window (Display over other apps)

    try {
      if (Platform.isAndroid) {
         // Moved SystemAlertWindow request to Dashboards via AutoStartHelper
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
        android: AndroidInitializationSettings('@drawable/ic_notification'),
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

    // Pre-create CallKit ongoing channel to prevent Android 8+ foreground service crash
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'callkit_ongoing_channel_id',
        'Ongoing Call',
        description: 'Ongoing Call Notification',
        importance: Importance.low,
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

    // Note: Backend already checks if the expert is online before sending FCM.
    // We trust the backend and just process the notification.

    if (type == 'call') {
      // The app is in the foreground. User requested native CallKit UI here too.
      await _showCallkitIncoming(data);
    } else if (type == 'message') {
      // User requested not to show heads-up notifications when the app is in the foreground.
      // The chat screen will update automatically via Firestore streams.
      debugPrint('[FCM] Received message in foreground, skipping local notification.');
    }
  }

  // ── BACKGROUND TAP HANDLER ────────────────────────────────────────────

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] Notification tapped from background: ${message.data}');
    _routeFromNotification(message.data);
  }

  void _routeFromNotification(Map<String, dynamic> data) {
    if (data['type'] == 'message') {
      int retries = 0;
      void pushRoute() {
        final currentState = navigatorKey?.currentState;
        
        if (currentState != null) {
          try {
            currentState.pushNamed(
              '/chat',
              arguments: <String, dynamic>{
                'otherUid': data['senderId'] ?? '',
                'otherUserName': data['senderName'] ?? 'User',
              },
            );
            debugPrint('[FCM] Successfully routed to chat!');
          } catch (e) {
            debugPrint('[FCM] Error routing to chat: $e');
            if (retries < 20) {
              retries++;
              Future.delayed(const Duration(milliseconds: 500), pushRoute);
            }
          }
        } else {
          if (retries < 20) {
            retries++;
            Future.delayed(const Duration(milliseconds: 500), pushRoute);
          }
        }
      }
      // Wait slightly before the first try to ensure UI is ready
      Future.delayed(const Duration(milliseconds: 300), pushRoute);
    }
  }

  // ── CALLKIT EVENT LISTENER ────────────────────────────────────────────

  /// Listens to OS-level CallKit events.
  /// On Accept → navigates to ActiveCallPage.
  /// On Decline → marks call as 'ended' in Firestore.
  void _listenCallKitEvents() {
    // Fallback: Listen to Native MainActivity intent for "Accept"
    final channel = MethodChannel('com.sajnire.app/auth');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onCallAcceptFallback') {
        final callRoomId = call.arguments as String?;
        debugPrint('[CallKit] Accepted via Fallback: $callRoomId');
        FlutterRingtonePlayer().stop();
        if (callRoomId != null) {
          final prefs = await SharedPreferences.getInstance();
          final storedCallerName = prefs.getString('callerName_$callRoomId');
          final resolvedName = storedCallerName ?? NotificationService.lastCallerName ?? 'Unknown';
          final resolvedCallerId = prefs.getString('callerId_$callRoomId') ?? '';

          void pushRoute() {
            if (navigatorKey?.currentState != null) {
              navigatorKey!.currentState!.pushNamed(
                '/active-call',
                arguments: <String, dynamic>{
                  'callRoomId': callRoomId,
                  'callerName': resolvedName,
                  'callerId': resolvedCallerId,
                },
              );
            } else {
              Future.delayed(const Duration(milliseconds: 200), pushRoute);
            }
          }
          pushRoute();
        }
      }
    });

    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      debugPrint('[CallKit] Event: ${event.eventName}');

      if (event is CallEventActionCallAccept) {
        FlutterRingtonePlayer().stop();
        // The UUID we passed as CallKitParams.id equals the Firestore callRoomId
        final callRoomId = event.callKitParams.id;
        debugPrint('[CallKit] Accepted: $callRoomId');

        // Navigate to active call screen
        // If app was killed, navigatorKey.currentState might be null briefly.
        // We poll for it to become ready before pushing.
        final prefs = await SharedPreferences.getInstance();
        final storedCallerName = prefs.getString('callerName_$callRoomId');
        final resolvedName = storedCallerName ?? NotificationService.lastCallerName ?? 'Unknown';
        final resolvedCallerId = prefs.getString('callerId_$callRoomId') ?? '';

        void pushRoute() {
          if (navigatorKey?.currentState != null) {
            navigatorKey!.currentState!.pushNamed(
              '/active-call',
              arguments: <String, dynamic>{
                'callRoomId': callRoomId,
                'callerName': resolvedName,
                'callerId': resolvedCallerId,
              },
            );
          } else {
            Future.delayed(const Duration(milliseconds: 200), pushRoute);
          }
        }
        pushRoute();
      } else if (event is CallEventActionCallDecline) {
        FlutterRingtonePlayer().stop();
        final callRoomId = event.callKitParams.id;
        debugPrint('[CallKit] Declined: $callRoomId');

        // End call properly via CallService (this also unlocks both users in RTDB)
        if (callRoomId.isNotEmpty) {
          try {
            await CallService().endCall(callRoomId);
          } catch (e) {
            debugPrint('[CallKit] RTDB error: $e');
          }
        }
      } else if (event is CallEventActionCallTimeout) {
        final callRoomId = event.id;
        debugPrint('[CallKit] Call timed out.');
        
        // End call properly via CallService to release locks
        if (callRoomId.isNotEmpty) {
           await CallService().endCall(callRoomId);
        }
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
