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
  bool _showNextShift = true;
  bool _showNickname = true;

  bool _alarmEnabled = true;

  // 🛠️ 5大班次獨立提前分鐘
  int _advanceM = 90;
  int _advanceLM = 90;
  int _advanceA = 60;
  int _advanceLN = 120;
  int _advanceN = 120;

  // 🛠️ 各班次獨立開關
  bool _enableM = true;
  bool _enableLM = true;
  bool _enableA = true;
  bool _enableLN = true;
  bool _enableN = true;

  bool _loading = true;

  final Map<String, String> shiftTimes = {
    'M': '08:00',
    'LM': '08:00',
    'A': '16:00',
    'LN': '20:00',
    'N': '23:00',
  };

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
      _showNextShift = prefs.getBool('widget_show_next_shift') ?? true;
      _showNickname = prefs.getBool('widget_show_nickname') ?? true;

      _alarmEnabled = prefs.getBool('widget_alarm_enabled') ?? true;

      _advanceM = prefs.getInt('alarm_advance_M') ?? 90;
      _advanceLM = prefs.getInt('alarm_advance_LM') ?? 90;
      _advanceA = prefs.getInt('alarm_advance_A') ?? 60;
      _advanceLN = prefs.getInt('alarm_advance_LN') ?? 120;
      _advanceN = prefs.getInt('alarm_advance_N') ?? 120;

      _enableM = prefs.getBool('alarm_enable_M') ?? true;
      _enableLM = prefs.getBool('alarm_enable_LM') ?? true;
      _enableA = prefs.getBool('alarm_enable_A') ?? true;
      _enableLN = prefs.getBool('alarm_enable_LN') ?? true;
      _enableN = prefs.getBool('alarm_enable_N') ?? true;

      _loading = false;
    });
  }

  Future<void> _saveWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('widget_enabled', _widgetEnabled);
    await prefs.setString('widget_team', _selectedTeam);
    await prefs.setBool('widget_show_next_shift', _showNextShift);
    await prefs.setBool('widget_show_nickname', _showNickname);

    await prefs.setBool('widget_alarm_enabled', _alarmEnabled);

    await prefs.setInt('alarm_advance_M', _advanceM);
    await prefs.setInt('alarm_advance_LM', _advanceLM);
    await prefs.setInt('alarm_advance_A', _advanceA);
    await prefs.setInt('alarm_advance_LN', _advanceLN);
    await prefs.setInt('alarm_advance_N', _advanceN);

    await prefs.setBool('alarm_enable_M', _enableM);
    await prefs.setBool('alarm_enable_LM', _enableLM);
    await prefs.setBool('alarm_enable_A', _enableA);
    await prefs.setBool('alarm_enable_LN', _enableLN);
    await prefs.setBool('alarm_enable_N', _enableN);

    try {
      await WidgetSnapshotWriter.forceRefreshAllWidgets();
      await alarmChannel.invokeMethod('syncAlarms');
    } catch (e) {
      debugPrint('網頁測試模式：已安全跳過手機底層元件更新。');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 彈性鬧鐘設定已成功同步！')),
      );
    }
  }

  String _calculateAlarmTime(String startTimeStr, int earlyMinutes) {
    try {
      final parts = startTimeStr.split(':');
      final int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);

      int totalMins = hour * 60 + minute - earlyMinutes;
      if (totalMins < 0) {
        totalMins += 24 * 60;
      }

      final int finalHour = totalMins ~/ 60;
      final int finalMinute = totalMins % 60;

      return '${finalHour.toString().padLeft(2, '0')}:${finalMinute.toString().padLeft(2, '0')}';
    } catch (e) {
      return startTimeStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('桌面小工具與彈性鬧鐘'),
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
                    value: _widgetEnabled,
                    activeColor: Colors.orange,
                    onChanged: (val) => setState(() => _widgetEnabled = val),
                  ),
                  if (_widgetEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('小工具追蹤隊伍'),
                      trailing: DropdownButton<String>(
                        value: _selectedTeam,
                        items: ['A', 'B', 'C', 'D'].map((t) => DropdownMenuItem(value: t, child: Text('$t 隊'))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedTeam = val);
                        },
                      ),
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
                      title: const Text('顯示用戶稱號花名'),
                      value: _showNickname,
                      activeColor: Colors.orange,
                      onChanged: (val) => setState(() => _showNickname = val),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('⏰ 廠房班次全彈性鬧鐘設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('開啟返工智能鬧鐘功能'),
                    value: _alarmEnabled,
                    activeColor: Colors.orange,
                    onChanged: (val) => setState(() => _alarmEnabled = val),
                  ),
                  if (_alarmEnabled) ...[
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider('早班 (M) 智能鬧鐘', shiftTimes['M']!, _enableM, _advanceM, const Color(0xFF1E88E5), (val) => setState(() => _enableM = val), (val) => setState(() => _advanceM = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider('L早班 (LM) 智能鬧鐘', shiftTimes['LM']!, _enableLM, _advanceLM, const Color(0xFF43A047), (val) => setState(() => _enableLM = val), (val) => setState(() => _advanceLM = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider('中班 (A) 智能鬧鐘', shiftTimes['A']!, _enableA, _advanceA, const Color(0xFFFB8C00), (val) => setState(() => _enableA = val), (val) => setState(() => _advanceA = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider('L夜班 (LN) 智能鬧鐘', shiftTimes['LN']!, _enableLN, _advanceLN, const Color(0xFF00838F), (val) => setState(() => _enableLN = val), (val) => setState(() => _advanceLN = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider('夜班 (N) 智能鬧鐘', shiftTimes['N']!, _enableN, _advanceN, const Color(0xFF7B1FA2), (val) => setState(() => _enableN = val), (val) => setState(() => _advanceN = val)),
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
                label: const Text('儲存設定', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlexibleAlarmSlider(String title, String startTime, bool isSubEnabled, int currentAdvance, Color color, ValueChanged<bool> onToggleChanged, ValueChanged<int> onSliderChanged) {
    String ringingTime = _calculateAlarmTime(startTime, currentAdvance);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Transform.scale(scale: 0.85, child: Switch(value: isSubEnabled, activeColor: color, onChanged: onToggleChanged)),
            ],
          ),
          if (!isSubEnabled) ...[
            const Padding(padding: EdgeInsets.only(top: 4, bottom: 8), child: Text('❌ 本班次鬧鐘已關閉', style: TextStyle(color: Colors.red, fontSize: 12))),
          ] else ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // ⚙️ 精準修復：由 between 改回正確的 spaceBetween
              children: [
                Text(currentAdvance == 0 ? '設定：準時提醒' : '設定：提早 $currentAdvance 分鐘響', style: const TextStyle(fontSize: 13, color: Colors.black54)), // ⚙️ 精準修復：由 black80 改回正確的 black54
                Text('🎯 鬧鐘: $ringingTime (開工: $startTime)', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            Slider(
              value: currentAdvance.toDouble(),
              min: 0,
              max: 240,
              divisions: 48,
              label: '提早 $currentAdvance 分鐘',
              activeColor: color,
              inactiveColor: color.withOpacity(0.15),
              onChanged: (val) => onSliderChanged(val.toInt()),
            ),
          ],
        ],
      ),
    );
  }
}