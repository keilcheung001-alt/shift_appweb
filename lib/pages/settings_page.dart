import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/constants/constants.dart';
import 'package:shift_app/utils/auth_util.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:battery_optimization_permission/battery_optimization_permission.dart';

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
  bool _isBatteryOptimizationIgnored = false;

  @override
  void initState() {
    super.initState();
    _loadThresholds();
    _loadPermissionCode();
    _checkBatteryOptimization();
  }

  Future<void> _checkBatteryOptimization() async {
    if (kIsWeb) return;
    final isIgnored = await BatteryOptimizationPermission.isIgnoringBatteryOptimizations();
    setState(() {
      _isBatteryOptimizationIgnored = isIgnored;
    });
  }

  Future<void> _requestBatteryOptimization() async {
    if (kIsWeb) return;
    // 彈出系統對話框請求用戶允許忽略電池優化
    final isSuccess = await BatteryOptimizationPermission.requestIgnoreBatteryOptimizations();
    if (isSuccess) {
      setState(() {
        _isBatteryOptimizationIgnored = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已成功加入電池白名單，鬧鐘將更準確')),
        );
      }
    } else {
      // 用戶可能拒絕或取消，可以手動引導至系統設定頁
      final opened = await BatteryOptimizationPermission.openBatteryOptimizationSettings();
      if (opened) {
        // 用戶從設定頁返回後，重新檢查狀態
        await _checkBatteryOptimization();
        if (_isBatteryOptimizationIgnored) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 設定完成，鬧鐘將正常運作')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ 請手動將本應用程式設為「不優化」')),
          );
        }
      }
    }
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

  // 保留舊的系統設定入口（可選）
  void _openAndroidSettings() {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('網頁版環境下無需設定 Android 系統權限')),
      );
      return;
    }
    // 打開應用程式詳細設定頁面（用戶可手動調整權限）
    try {
      BatteryOptimizationPermission.openApplicationSettings();
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
                // 權限狀態卡片
                ListTile(
                  leading: const Icon(Icons.verified_user, color: Colors.indigo),
                  title: const Text('當前帳號權限層級'),
                  subtitle: Text(_permissionCode ?? '加載中…'),
                ),
                const Divider(),

                // 鬧鐘可靠性設定（新增）
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.alarm, color: Colors.deepOrange),
                            SizedBox(width: 12),
                            Text('鬧鐘可靠性設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          kIsWeb
                              ? '網頁版無需設定'
                              : '為確保「工作鬧鐘」在手機休眠或省電模式下也能準時響起，請將此應用加入「電池優化白名單」。',
                          style: const TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        if (!kIsWeb)
                          Row(
                            children: [
                              Icon(
                                _isBatteryOptimizationIgnored ? Icons.check_circle : Icons.warning,
                                color: _isBatteryOptimizationIgnored ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isBatteryOptimizationIgnored
                                      ? '已加入白名單，鬧鐘將正常運作 ✅'
                                      : '尚未加入白名單，鬧鐘可能不準 ⚠️',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _isBatteryOptimizationIgnored ? Colors.green : Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        if (!kIsWeb)
                          ElevatedButton.icon(
                            onPressed: _requestBatteryOptimization,
                            icon: const Icon(Icons.battery_charging_full),
                            label: const Text('🔋 一鍵修復鬧鐘（加入白名單）'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(),

                // 人數門檻值調整
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

                // 其他系統權限（進階）
                ListTile(
                  leading: const Icon(Icons.settings_applications, color: Colors.grey),
                  title: const Text('其他應用程式系統設定'),
                  subtitle: Text(kIsWeb ? '網頁環境（已自動停用）' : '前往手動調整權限、通知等'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !kIsWeb,
                  onTap: _openAndroidSettings,
                ),
              ],
            ),
    );
  }
}