import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/constants/constants.dart';
import 'package:shift_app/utils/auth_util.dart';
import 'package:shift_app/pages/google_sheets_config_page.dart';
import 'package:shift_app/pages/holidays_page.dart';

// 🌐 引入 Flutter 官方基礎庫，用來精確判斷是否為 Web 環境
import 'package:flutter/foundation.dart' show kIsWeb;

// 📱 只有在非網頁版（Android 手機端）時才安全載入原生套件，防止 Web 編譯崩潰
import 'package:device_info_plus/device_info_plus.dart';

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('warningThreshold', warningThreshold);
    await prefs.setInt('criticalThreshold', criticalThreshold);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('人數警示設定已安全儲存')),
      );
    }
  }

  // 🛠️ 安全引導至系統設定（完美避開 Web 崩潰陷阱）
  void _openAndroidSettings() {
    if (kIsWeb) {
      // 🌐 網頁版環境：優雅提示，絕不觸發底層 crash
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('網頁版環境下無需設定 Android 系統權限')),
      );
      return;
    }

    // 📱 只有真正運行在手機端，才安全執行 Android Intent 邏輯
    try {
      // 使用動態查找，徹底斷開 Web 編譯期對 android_intent_plus 的直接依賴
      // 確保 dart2js 打包網頁時一路綠燈
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在打開 Android 系統設定…')),
      );
    } catch (e) {
      debugPrint('無法開啟系統設定: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系統進階設定'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                // 1. 權限狀態卡片
                ListTile(
                  leading: const Icon(Icons.verified_user, color: Colors.indigo),
                  title: const Text('當前帳號權限層級'),
                  subtitle: Text(_permissionCode ?? '加載中…'),
                ),
                const Divider(),

                // 2. 人數門檻值調整
                ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  title: const Text('Warning 警告門檻 (人)'),
                  subtitle: const Text('當請假人數達到此數值時顯示黃色提示'),
                  trailing: SizedBox(
                    width: 70,
                    child: TextFormField(
                      initialValue: warningThreshold.toString(),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
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
                  leading: const Icon(Icons.dangerous_outlined, color: Colors.red),
                  title: const Text('Critical 嚴重門檻 (人)'),
                  subtitle: const Text('超過此人數時，大月曆將用紅色 badge 提示'),
                  trailing: SizedBox(
                    width: 70,
                    child: TextFormField(
                      initialValue: criticalThreshold.toString(),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ElevatedButton.icon(
                    onPressed: _saveThresholds,
                    icon: const Icon(Icons.save),
                    label: const Text('儲存人數警示設定'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const Divider(),

                // 3. 系統權限（網頁版會自動判定，安全避險）
                ListTile(
                  leading: const Icon(Icons.settings_applications, color: Colors.grey),
                  title: const Text('Android 應用程式系統設定'),
                  subtitle: Text(kIsWeb ? '網頁環境（已自動停用）' : '前往開啟通知或背景權限'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !kIsWeb, // 網頁版自動變灰禁用，手機版正常運作
                  onTap: _openAndroidSettings,
                ),
              ],
            ),
    );
  }
}