import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'constants/constants.dart';
import 'screens/login_page.dart';
// 💡 核心修正：只引入正確的 desktop_widgets_page，徹底移除舊有 team_menu_page 的引入，防止撞名
import 'pages/desktop_widgets_page.dart';

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
      // 🚀 預設進到前台防窺版的登入畫面
      home: const LoginPage(),
      routes: {
        ROUTE_LOGIN: (context) => const LoginPage(),

        // 🎯 核心修正一：將原本指向 TeamMenuPage 的舊路由，完美導向至整合好的 DesktopWidgetsPage
        ROUTE_TEAM_MENU: (context) => const DesktopWidgetsPage(),

        // 🎯 核心修正二：確保此處的 DesktopWidgetsPage 100% 來自唯一檔案，不再鬧雙胞
        ROUTE_DESKTOP_WIDGETS: (context) => const DesktopWidgetsPage(),
      },
    );
  }
}