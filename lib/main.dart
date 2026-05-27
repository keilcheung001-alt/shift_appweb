import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'constants/constants.dart';
import 'screens/login_page.dart';
import 'pages/team_menu_page.dart';
import 'pages/approval_page.dart';
import 'pages/holidays_page.dart';
import 'pages/google_sheets_config_page.dart';
import 'pages/whatsapp_config_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCyEv9MNjm2dxw63JrNrz37mp5o0drNxuE",
        appId: "1:281431943954:android:900073d0aac37fc7c821cb",
        messagingSenderId: "281431943954",
        projectId: "shift-app-firebase",
        storageBucket: "shift-app-firebase.firebasestorage.app",
      ),
    );
  } catch (e) {
    debugPrint('Firebase init error');
  }
  tz.initializeTimeZones();
  runApp(const TempoLeaveApp());
}

class TempoLeaveApp extends StatelessWidget {
  const TempoLeaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tempo Leave',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const LoginPage(),
      routes: {
        ROUTE_LOGIN: (context) => const LoginPage(),
        ROUTE_TEAM_MENU: (context) => const TeamMenuPage(),
        ROUTE_APPROVAL: (context) => const ApprovalPage(),
        ROUTE_HOLIDAYS: (context) => const HolidaysPage(),
        ROUTE_GOOGLE_SHEETS_CONFIG: (context) => const GoogleSheetsConfigPage(),
        ROUTE_WHATSAPP_CONFIG: (context) => const WhatsAppConfigPage(),
      },
    );
  }
}