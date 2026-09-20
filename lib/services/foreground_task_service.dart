import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

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
            ),
          ),
        );
      }
    }
  });

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    // Keep alive tick
  });
}
