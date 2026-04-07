import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/constants/constants.dart';
import 'package:shift_app/utils/auth_util.dart';
import 'package:shift_app/pages/google_sheets_config_page.dart';
import 'package:shift_app/pages/holidays_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int warningThreshold = 2;
  int criticalThreshold = 3;
  bool _loading = true;
  String? _permissionCode;

  @override
  void initState() {
    super.initState();
    _loadThresholds();
    _loadPermissionCode();
  }

  Future<void> _loadPermissionCode() async {
    final code = await AuthUtil.getPermissionCode();
    setState(() {
      _permissionCode = code;
    });
  }

  Future<void> _loadThresholds() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      warningThreshold = prefs.getInt('warningThreshold') ?? 2;
      criticalThreshold = prefs.getInt('criticalThreshold') ?? 3;
      _loading = false;
    });
  }

  Future<void> _saveThresholds() async {
    if (warningThreshold < 0) warningThreshold = 0;
    if (criticalThreshold < 0) criticalThreshold = 0;
    if (warningThreshold > criticalThreshold) {
      warningThreshold = criticalThreshold;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('warningThreshold', warningThreshold);
    await prefs.setInt('criticalThreshold', criticalThreshold);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 人數警示設定已儲存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        children: [
          const ListTile(
            title: Text(
              '系統設定',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),

          // Google Sheets / Apps Script 設定
          ListTile(
            leading: const Icon(Icons.table_chart),
            title: const Text('Google Sheets / Apps Script 設定'),
            subtitle: const Text('API Key、四隊 Sheet ID'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GoogleSheetsConfigPage(),
                ),
              );
            },
          ),
          const Divider(height: 1),

          // 假期管理
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('假期管理'),
            subtitle: const Text('公眾假期 + 自訂特別假期'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HolidaysPage(),
                ),
              );
            },
          ),
          const Divider(height: 1),

          // 公告管理（僅 SR 或 SM 可見）
          if (_permissionCode == 'SR' || _permissionCode == 'SM') ...[
            ListTile(
              leading: const Icon(Icons.announcement),
              title: const Text('公告管理'),
              onTap: () {
                Navigator.pushNamed(context, ROUTE_ADMIN_NOTIFICATIONS);
              },
            ),
            const Divider(height: 1),
          ],

          // 請假人數警示
          const ListTile(
            title: Text(
              '請假人數警示',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.warning_amber_rounded),
            title: const Text('Warning 門檻'),
            subtitle: const Text('少於 critical 時，用橙色 / 綠色顯示'),
            trailing: SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: warningThreshold.toString(),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n == null) return;
                  setState(() {
                    warningThreshold = n.clamp(0, 99);
                    if (warningThreshold > criticalThreshold) {
                      criticalThreshold = warningThreshold;
                    }
                  });
                },
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dangerous),
            title: const Text('Critical 門檻'),
            subtitle: const Text('超過時，用紅色 badge 提示'),
            trailing: SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: criticalThreshold.toString(),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n == null) return;
                  setState(() {
                    criticalThreshold = n.clamp(0, 99);
                    if (criticalThreshold < warningThreshold) {
                      warningThreshold = criticalThreshold;
                    }
                  });
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _saveThresholds,
              icon: const Icon(Icons.save),
              label: const Text('儲存人數警示設定'),
            ),
          ),
        ],
      ),
    );
  }
}