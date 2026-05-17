import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'firebase_options.dart';
import 'constants/constants.dart';
import 'screens/login_page.dart';
import 'pages/team_menu_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
        ROUTE_TEAM_MENU: (context) => const TeamMenuPage(),
      },
    );
  }
}