import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'constants/constants.dart';
import 'screens/login_page.dart';
import 'pages/desktop_widgets_page.dart';
// 💡 還原：重新引入你原汁原味的團隊主選單頁面，由它內部直接調用 A、B、C、D 隊大月曆
import 'package:shift_app/pages/team_menu_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const LoginPage(),
      routes: {
        ROUTE_LOGIN: (context) => const LoginPage(),

        // 🎯 完美歸位：登入後直接回到你最熟悉的 TeamMenuPage，看爆四組大月曆表！
        ROUTE_TEAM_MENU: (context) => const TeamMenuPage(),

        // 🎯 獨立存在：小工具專屬通道，兩者各司其職不打交
        ROUTE_DESKTOP_WIDGETS: (context) => const DesktopWidgetsPage(),
      },
    );
  }
}