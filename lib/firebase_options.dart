import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD_Gm-h-5CPldqwsDvlOPjXyqWFzYk4hmc',
    appId: '1:683266467920:web:abcdef1234567890', // Placeholder, might work for basic features
    messagingSenderId: '683266467920',
    projectId: 'zegochat-c44b0',
    authDomain: 'zegochat-c44b0.firebaseapp.com',
    storageBucket: 'zegochat-c44b0.firebasestorage.app',
    databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD_Gm-h-5CPldqwsDvlOPjXyqWFzYk4hmc',
    appId: '1:683266467920:android:97423f6ddf436b48860955',
    messagingSenderId: '683266467920',
    projectId: 'zegochat-c44b0',
    storageBucket: 'zegochat-c44b0.firebasestorage.app',
    databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD_Gm-h-5CPldqwsDvlOPjXyqWFzYk4hmc',
    appId: '1:683266467920:ios:97423f6ddf436b48860955',
    messagingSenderId: '683266467920',
    projectId: 'zegochat-c44b0',
    storageBucket: 'zegochat-c44b0.firebasestorage.app',
    databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyD_Gm-h-5CPldqwsDvlOPjXyqWFzYk4hmc',
    appId: '1:683266467920:web:abcdef1234567890',
    messagingSenderId: '683266467920',
    projectId: 'zegochat-c44b0',
    authDomain: 'zegochat-c44b0.firebaseapp.com',
    storageBucket: 'zegochat-c44b0.firebasestorage.app',
    databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
  );
}
