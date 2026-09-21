import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class ForegroundTaskService {
  static final ForegroundTaskService _instance = ForegroundTaskService._internal();

  factory ForegroundTaskService() {
    return _instance;
  }

  ForegroundTaskService._internal();

  static const String notificationChannelId = 'sajnire_foreground_service';
  static const int notificationId = 888;

  Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId, // id
      'Background Service', // title
      description: 'This channel is used for important notifications.',
      importance: Importance.low, // importance must be at low or higher level
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'SajniRe',
        initialNotificationContent: 'Waiting for calls...',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
  }

  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke("stopService");
    }
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize Crashlytics for the background isolate
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Listen to Firebase RTDB connection state
  final db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
  );
  
  db.ref('.info/connected').onValue.listen((event) async {
    final isConnected = event.snapshot.value == true;
    
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        flutterLocalNotificationsPlugin.show(
          id: ForegroundTaskService.notificationId,
          title: 'SajniRe',
          body: isConnected ? 'Online - Waiting for calls...' : 'Offline - No Internet Connection',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              ForegroundTaskService.notificationChannelId,
              'Background Service',
              icon: 'ic_launcher',
              ongoing: true,
              autoCancel: false,
            ),
          ),
        );
      }
    }

    if (isConnected) {
      // Internet restored while in background/locked state.
      // Re-publish the expert to the online queue to ensure they receive calls.
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final expertId = user.uid;
          final doc = await FirebaseFirestore.instance.collection('experts').doc(expertId).get();
          if (doc.exists) {
            final data = doc.data();
            final gender = data?['gender'] as String? ?? 'female';
            final language = data?['language'] as String? ?? 'hindi';
            final talkSeconds = (data?['totalTalkSeconds'] as num?)?.toInt() ?? 0;
            final nickname = data?['nickname'] as String? ?? 'Expert';
            final age = (data?['age'] as num?)?.toInt() ?? 22;
            final avatarUrl = data?['profileImageUrl'] as String? ?? data?['avatarUrl'] as String?;
            final avatarIndex = (data?['avatarIndex'] as num?)?.toInt() ?? 1;

            final presenceRef = db.ref('status/$expertId');
            final queueRef = db.ref('queues/${gender.toLowerCase()}_${language.toLowerCase()}/$expertId');

            await presenceRef.update({
              'isOnline': true,
              'status': 'online',
              'callStatus': 'available',
              'lastChanged': ServerValue.timestamp,
            });

            await presenceRef.onDisconnect().update({
              'isOnline': false,
              'status': 'offline',
              'callStatus': 'offline',
              'lastChanged': ServerValue.timestamp,
            });

            await queueRef.update({
              'timestamp': ServerValue.timestamp,
              'totalTalkSeconds': talkSeconds,
              'nickname': nickname,
              'age': age,
              'avatarIndex': avatarIndex,
              if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
            });
            await queueRef.onDisconnect().remove();
            
            // Clear any stuck active call locks
            await db.ref('active_calls/$expertId').remove();
          }
        }
      } catch (e) {
        debugPrint('Background reconnection error: $e');
      }
    }
  });

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    // Keep alive tick
  });
}
