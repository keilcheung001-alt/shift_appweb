import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firebase_options.dart';
import 'constants/constants.dart';
import 'screens/login_page.dart';
import 'pages/team_menu_page.dart';
import 'pages/full_calendar_a.dart';
import 'pages/full_calendar_b.dart';
import 'pages/full_calendar_c.dart';
import 'pages/full_calendar_d.dart';
import 'pages/approval_page.dart';
import 'pages/my_leave_page.dart';
import 'pages/cancel_leave_request_page.dart';
import 'pages/desktop_widgets_page.dart';
import 'pages/google_sheets_config_page.dart';
import 'pages/whatsapp_config_page.dart';
import 'pages/holidays_page.dart';
import 'utils/widget_snapshot_writer.dart';

final MethodChannel alarmChannel = MethodChannel('com.example.shift_app/alarm');

Future<void> requestPermissions() async {
  if (kIsWeb) return;

  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
  if (await Permission.scheduleExactAlarm.isDenied) {
    await Permission.scheduleExactAlarm.request();
  }
  if (await Permission.ignoreBatteryOptimizations.isDenied) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await requestPermissions();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('❌ Firebase 初始化失敗: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  final staffId = prefs.getString(SPK_STAFF_ID) ?? '';
  final group = prefs.getString(SPK_GROUP) ?? 'D';
  final permissionCode = prefs.getString(SPK_PERMISSION_CODE) ?? '';

  final bool isSuperAdmin = permissionCode == 'SM';
  final bool canFullEdit = isSuperAdmin || permissionCode == 'SR';

  runApp(TempoLeaveApp(
    isLoggedIn: staffId.isNotEmpty,
    staffId: staffId,
    group: group,
    canFullEdit: canFullEdit,
    isSuperAdmin: isSuperAdmin,
  ));
}

class TempoLeaveApp extends StatelessWidget {
  final bool isLoggedIn;
  final String staffId;
  final String group;
  final bool canFullEdit;
  final bool isSuperAdmin;

  const TempoLeaveApp({
    super.key,
    required this.isLoggedIn,
    required this.staffId,
    required this.group,
    required this.canFullEdit,
    required this.isSuperAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '排班請假系統',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      initialRoute: isLoggedIn ? ROUTE_TEAM_MENU : ROUTE_LOGIN,
      routes: {
        ROUTE_LOGIN: (context) => const LoginPage(),
        ROUTE_TEAM_MENU: (context) => TeamMenuPage(
          staffId: staffId,
          group: group,
          canFullEdit: canFullEdit,
          isSuperAdmin: isSuperAdmin,
        ),
        ROUTE_APPROVAL: (context) => const ApprovalPage(),
        ROUTE_MY_LEAVE: (context) => const MyLeavePage(),
        ROUTE_CANCEL_LEAVE: (context) => const CancelLeaveRequestPage(),
        ROUTE_DESKTOP_WIDGETS: (context) => const DesktopWidgetsPage(),
        ROUTE_HOLIDAYS: (context) => const HolidaysPage(),
        ROUTE_WHATSAPP_CONFIG: (context) => const WhatsAppConfigPage(),
        ROUTE_GOOGLE_SHEETS_CONFIG: (context) => const GoogleSheetsConfigPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == ROUTE_CALENDAR_A) {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (context) => FullCalendarATeam(
              staffId: args['staffId'] ?? staffId,
              teamCode: args['teamCode'] ?? 'D',
              canFullEdit: args['canFullEdit'] ?? canFullEdit,
              isSuperAdmin: args['isSuperAdmin'] ?? isSuperAdmin,
            ),
          );
        }
        if (settings.name == ROUTE_CALENDAR_B) {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (context) => FullCalendarBTeam(
              staffId: args['staffId'] ?? staffId,
              teamCode: args['teamCode'] ?? 'D',
              canFullEdit: args['canFullEdit'] ?? canFullEdit,
              isSuperAdmin: args['isSuperAdmin'] ?? isSuperAdmin,
            ),
          );
        }
        if (settings.name == ROUTE_CALENDAR_C) {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (context) => FullCalendarCTeam(
              staffId: args['staffId'] ?? staffId,
              teamCode: args['teamCode'] ?? 'D',
              canFullEdit: args['canFullEdit'] ?? canFullEdit,
              isSuperAdmin: args['isSuperAdmin'] ?? isSuperAdmin,
            ),
          );
        }
        if (settings.name == ROUTE_CALENDAR_D) {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (context) => FullCalendarDTeam(
              staffId: args['staffId'] ?? staffId,
              teamCode: args['teamCode'] ?? 'D',
              canFullEdit: args['canFullEdit'] ?? canFullEdit,
              isSuperAdmin: args['isSuperAdmin'] ?? isSuperAdmin,
            ),
          );
        }
        return null;
      },
    );
  }
}