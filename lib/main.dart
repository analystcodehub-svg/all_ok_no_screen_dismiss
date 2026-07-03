import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'providers/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/active_call_page.dart';
import 'screens/auth_wrapper.dart';
import 'services/notification_service.dart';

/// Global navigator key — used by NotificationService to navigate
/// after a call is accepted from the background / lock screen.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Initialize Firebase ──────────────────────────────────────────────
  bool firebaseInitialized = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseInitialized = true;
    debugPrint('Firebase initialized successfully.');
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  // ── 2. Initialize Notification Service (FCM + CallKit) ─────────────────
  if (firebaseInitialized) {
    await NotificationService.instance.initialize(navKey: navigatorKey);
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const SajniReApp(),
    ),
  );
}

class SajniReApp extends StatelessWidget {
  const SajniReApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SajniRe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,

      // Provide the global navigatorKey so NotificationService can
      // push routes after accepting a call from a terminated state.
      navigatorKey: navigatorKey,

      home: const AuthWrapper(),

      // Named routes used by NotificationService._listenCallKitEvents()
      routes: {
        '/active-call': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return ActiveCallPage(
            callRoomId: args['callRoomId'] as String,
            receiverId: '',      // Will be resolved inside ActiveCallPage
            callerId:   args['callerName'] as String,
            nickname:   args['callerName'] as String,
            pricePerMin: 5.0,
            isCaller: false,     // Receiver is accepting
          );
        },
      },
    );
  }
}
