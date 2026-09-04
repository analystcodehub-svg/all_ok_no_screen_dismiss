import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'providers/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/active_call_page.dart';
import 'screens/auth_wrapper.dart';
import 'services/notification_service.dart';
import 'services/foreground_task_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'screens/maintenance_screen.dart';
import 'screens/hybrid_chat_screen.dart';

/// Global navigator key — used by NotificationService to navigate
/// after a call is accepted from the background / lock screen.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock app to portrait mode — prevents overflow on landscape rotation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Always show status bar (network, battery, time) and navigation bar
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

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
    AppState.syncPendingChatDeductions();
    await NotificationService.instance.initialize(navKey: navigatorKey);
    // Initialize Foreground Task Service
    await ForegroundTaskService().initializeService();
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

      builder: (context, child) {
        return StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref('app_settings/maintenance_mode').onValue,
          builder: (context, snapshot) {
            bool isMaintenance = false;
            if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
              final value = snapshot.data!.snapshot.value;
              if (value is bool) {
                isMaintenance = value;
              } else if (value is String) {
                isMaintenance = value.toLowerCase() == 'true';
              }
            }
            
            if (isMaintenance) {
              return const MaintenanceScreen();
            }
            
            return child ?? const SizedBox.shrink();
          },
        );
      },

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
        '/chat': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          final appState = Provider.of<AppState>(context, listen: false);
          return HybridChatScreen(
            myUid: appState.uid,
            otherUid: args['otherUid'] as String,
            otherUserName: args['otherUserName'] as String,
          );
        },
      },
    );
  }
}
