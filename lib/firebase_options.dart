import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show
defaultTargetPlatform, kIsWeb, TargetPlatform;

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
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBAf1Vi987cm0rinRORNqM1BX5_XAot5kI',
    appId: '1:281431943954:web:900073d0aac37fc7c821cb',
    messagingSenderId: '281431943954',
    projectId: 'shift-app-firebase',
    authDomain: 'shift-app-firebase.firebaseapp.com',
    storageBucket: 'shift-app-firebase.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBAf1Vi987cm0rinRORNqM1BX5_XAot5kI',
    appId: '1:281431943954:android:900073d0aac37fc7c821cb',
    messagingSenderId: '281431943954',
    projectId: 'shift-app-firebase',
    storageBucket: 'shift-app-firebase.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyATlsWLYk2eJvfBjhLAPcvwNsvNsUMvu4U', // 用 plist 入面嗰隻 key
    appId: '1:281431943954:ios:d47d48937cf4b328c821cb', // 用 plist GOOGLE_APP_ID
    messagingSenderId: '281431943954',
    projectId: 'shift-app-firebase',
    storageBucket: 'shift-app-firebase.firebasestorage.app',
    iosBundleId: 'com.example.shiftApp',
  );
}
