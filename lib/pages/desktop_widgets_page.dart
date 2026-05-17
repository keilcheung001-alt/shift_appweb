import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

import '../utils/auth_util.dart';
import '../utils/widget_snapshot_writer.dart';
import '../constants/constants.dart';

final MethodChannel alarmChannel = MethodChannel('com.example.shift_app/alarm');

class DesktopWidgetsPage extends StatefulWidget {
  const DesktopWidgetsPage({super.key});

  @override
  State<DesktopWidgetsPage> createState() => _DesktopWidgetsPageState();
}

class _DesktopWidgetsPageState extends State<DesktopWidgetsPage> {
  bool _widgetEnabled = true;
  String _selectedTeam = 'A';
  bool _showLeaveCount = true;
  bool _showNextShift = true;
  bool _showNickname = true;

  // 🎯 核心修改一：已徹底移除舊有 [_updateTimes] 與 [_selectedUpdateIndex] 定時更新變數

  // 鬧鐘開關（預設啟用）
  bool _alarmEnabled = true;
  // 提前多少分鐘響鬧鐘（預設 60 分鐘，上限 240 分鐘即 4 小時）
  int _alarmAdvanceMinutes = 60;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _loadWidgetSettings();
  }

  Future<void> _loadWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _widgetEnabled = prefs.getBool('widget_enabled') ?? true;
      _selectedTeam = prefs.getString('widget_team') ?? 'A';
      _showLeaveCount = prefs.getBool('widget_show_leave_count') ?? true;
      _showNextShift = prefs.getBool('widget_show_next_shift') ?? true;
      _showNickname = prefs.getBool('widget_show_nickname') ?? true;

      _alarmEnabled = prefs.getBool('widget_alarm_enabled') ?? true;
      _alarmAdvanceMinutes = prefs.getInt('widget_alarm_advance_minutes') ?? 60;

      _loading = false;
    });
  }

  Future<void> _saveWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('widget_enabled', _widgetEnabled);
    await prefs.setString('widget_team', _selectedTeam);
    await prefs.setBool('widget_show_leave_count', _showLeaveCount);
    await prefs.setBool('widget_show_next_shift', _showNextShift);
    await prefs.setBool('widget_show_nickname', _showNickname);

    await prefs.setBool('widget_alarm_enabled', _alarmEnabled);
    await prefs.setInt('widget_alarm_advance_minutes', _alarmAdvanceMinutes);

    // 重新產生小工具快照與更新鬧鐘排程
    await WidgetSnapshotWriter.updateSnapshotAndAlarms();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 設定已成功儲存，小工具與鬧鐘已同步！')),
      );
    }
  }

  Future<void> _updateAdvanceMinutes(int value) async {
    setState(() {
      _alarmAdvanceMinutes = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('widget_alarm_advance_minutes', _alarmAdvanceMinutes);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('小工具與鬧鐘設定'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📱 桌面小工具配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('啟用桌面小工具功能'),
                    subtitle: const Text('關閉後小工具將停止更新'),
                    value: _widgetEnabled,
                    activeColor: Colors.orange,
                    onChanged: (val) {
                      setState(() => _widgetEnabled = val);
                    },
                  ),
                  if (_widgetEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('小工具追蹤隊伍'),
                      subtitle: const Text('選擇要在桌面上顯示哪一隊的更表'),
                      trailing: DropdownButton<String>(
                        value: _selectedTeam,
                        items: ['A', 'B', 'C', 'D'].map((t) {
                          return DropdownMenuItem(value: t, child: Text('$t 隊'));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedTeam = val);
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('顯示個人假期統計'),
                      value: _showLeaveCount,
                      activeColor: Colors.orange,
                      onChanged: (val) => setState(() => _showLeaveCount = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('顯示下一班次預告'),
                      value: _showNextShift,
                      activeColor: Colors.orange,
                      onChanged: (val) => setState(() => _showNextShift = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('顯示用戶暱稱'),
                      value: _showNickname,
                      activeColor: Colors.orange,
                      onChanged: (val) => setState(() => _showNickname = val),
                    ),
                    // 🎯 核心修改二：已在此處彻底移除原本無用的「定時更新頻率」ListTile 區塊
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('⏰ 智能上班鬧鐘設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('開啟返工智能鬧鐘'),
                    subtitle: const Text('跟隨更表自動響鬧，請假核准當日自動取消'),
                    value: _alarmEnabled,
                    activeColor: Colors.orange,
                    onChanged: (val) {
                      setState(() => _alarmEnabled = val);
                    },
                  ),
                  if (_alarmEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('鬧鐘提前提醒時間'),
                      subtitle: Text('目前設定：提前 $_alarmAdvanceMinutes 分鐘響鈴 (${(_alarmAdvanceMinutes / 60).toStringAsFixed(1)} 小時)'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                            onPressed: () {
                              // 🔒 確保最少提前 5 分鐘，最多 240 分鐘（4小時）
                              final newVal = (_alarmAdvanceMinutes - 5).clamp(5, 240);
                              _updateAdvanceMinutes(newVal);
                            },
                          ),
                          Text('$_alarmAdvanceMinutes 🚀', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.orange),
                            onPressed: () {
                              final newVal = (_alarmAdvanceMinutes + 5).clamp(5, 240);
                              _updateAdvanceMinutes(newVal);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveWidgetSettings,
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text('保存並即時同步設定', style: TextStyle(fontSize: 16, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ℹ️ 小工具與智能鬧鐘説明', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('• 桌面小工具會實時顯示今日及未來兩日班次', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 需要在手機桌面添加 "Tempo Leave" Widget', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 長按手機桌面空白位置 > 加入 Widget', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 鬧鐘會喺班次開始前準時提醒你（最高支援提早 4 小時）', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 當你在 App 內請假成功且管理員核准後，當日鬧鐘會全自動取消，無需手動關閉', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}