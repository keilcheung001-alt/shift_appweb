import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'firebase_options.dart';
import 'constants/constants.dart';
import 'screens/login_page.dart';
import 'pages/team_menu_page.dart';
import 'pages/approval_page.dart';
import 'pages/holidays_page.dart';
import 'pages/google_sheets_config_page.dart';
import 'pages/whatsapp_config_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 確保 Firebase 初始化失敗唔會令 App 死，用 try-catch 包住
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase 初始化失敗: $e');
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