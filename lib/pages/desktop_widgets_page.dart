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

  // 鬧鐘總開關
  bool _alarmEnabled = true;

  // 🎯 5大班次各自獨立的「提前分鐘數」（起始設定保留充足彈性，供用戶自行向前向後跳）
  int _advanceM = 90;   // 早班預設 90 分鐘（留充足時間搭廠車）
  int _advanceLM = 90;  // L早班預設 90 分鐘
  int _advanceA = 60;   // 中班預設 60 分鐘
  int _advanceLN = 120; // L夜班預設 120 分鐘
  int _advanceN = 120;  // 夜班預設 120 分鐘

  // 🎯 核心新增：5大班次各自獨立的「鬧鐘啟用開關」（唔想響嘅班次可以直接閂咗佢，極致彈性）
  bool _enableM = true;
  bool _enableLM = true;
  bool _enableA = true;
  bool _enableLN = true;
  bool _enableN = true;

  bool _loading = true;

  // 🕒 100% 採用廠房真正開工時間
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

      // 載入 5 個班次獨立的提前分鐘數
      _advanceM = prefs.getInt('alarm_advance_M') ?? 90;
      _advanceLM = prefs.getInt('alarm_advance_LM') ?? 90;
      _advanceA = prefs.getInt('alarm_advance_A') ?? 60;
      _advanceLN = prefs.getInt('alarm_advance_LN') ?? 120;
      _advanceN = prefs.getInt('alarm_advance_N') ?? 120;

      // 載入 5 個班次獨立的開關狀態
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

    // 儲存 5 個班次獨立的提前分鐘數
    await prefs.setInt('alarm_advance_M', _advanceM);
    await prefs.setInt('alarm_advance_LM', _advanceLM);
    await prefs.setInt('alarm_advance_A', _advanceA);
    await prefs.setInt('alarm_advance_LN', _advanceLN);
    await prefs.setInt('alarm_advance_N', _advanceN);

    // 儲存 5 個班次獨立的開關狀態
    await prefs.setBool('alarm_enable_M', _enableM);
    await prefs.setBool('alarm_enable_LM', _enableLM);
    await prefs.setBool('alarm_enable_A', _enableA);
    await prefs.setBool('alarm_enable_LN', _enableLN);
    await prefs.setBool('alarm_enable_N', _enableN);

    try {
      await WidgetSnapshotWriter.forceRefreshAllWidgets();
      await alarmChannel.invokeMethod('syncAlarms'); // 全面同步最新智能鬧鐘到手機系統
    } catch (e) {
      debugPrint('Sync failed: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('💾 5組獨立彈性鬧鐘已安全同步！已完美適配你的返工出行習慣。')),
      );
    }
  }

  // 🧮 精準動態減數邏輯
  String _calculateAlarmTime(String startTimeStr, int earlyMinutes) {
    try {
      final parts = startTimeStr.split(':');
      final int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);

      int totalMins = hour * 60 + minute - earlyMinutes;
      if (totalMins < 0) {
        totalMins += 24 * 60; // 跨日處理
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
        title: const Text('桌面小工具與全彈性鬧鐘'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 本地隱私卡片
            Card(
              color: Colors.grey[900],
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.tune, color: Colors.greenAccent, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '🔒 彈性控制台：每班獨立開關及時間扣減，完全滿足揸車、搭廠車或住公司隔離的個人化需求。',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 📱 桌面小工具配置
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

            // ⏰ 智能上班鬧鐘設定
            const Text('⏰ 廠房班次全彈性鬧鐘設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('可隨意調整各更次的提前響鬧時間。如某個班次不需要鬧鐘，可直接關閉該班次開關。', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('開啟返工智能鬧鐘功能'),
                    subtitle: const Text('開啟後，系統會自動對照你登入隊伍的當天更表執行對應鬧鐘。'),
                    value: _alarmEnabled,
                    activeColor: Colors.orange,
                    onChanged: (val) => setState(() => _alarmEnabled = val),
                  ),
                  if (_alarmEnabled) ...[
                    const Divider(height: 1),

                    // 1. 早班 (M)
                    _buildFlexibleAlarmSlider(
                      title: '早班 (M) 智能鬧鐘',
                      startTime: shiftTimes['M']!,
                      isSubEnabled: _enableM,
                      currentAdvance: _advanceM,
                      color: const Color(0xFF1E88E5),
                      onToggleChanged: (val) => setState(() => _enableM = val),
                      onSliderChanged: (val) => setState(() => _advanceM = val),
                    ),
                    const Divider(height: 1),

                    // 2. L早班 (LM)
                    _buildFlexibleAlarmSlider(
                      title: 'L早班 (LM) 智能鬧鐘',
                      startTime: shiftTimes['LM']!,
                      isSubEnabled: _enableLM,
                      currentAdvance: _advanceLM,
                      color: const Color(0xFF43A047),
                      onToggleChanged: (val) => setState(() => _enableLM = val),
                      onSliderChanged: (val) => setState(() => _advanceLM = val),
                    ),
                    const Divider(height: 1),

                    // 3. 中班 (A)
                    _buildFlexibleAlarmSlider(
                      title: '中班 (A) 智能鬧鐘',
                      startTime: shiftTimes['A']!,
                      isSubEnabled: _enableA,
                      currentAdvance: _advanceA,
                      color: const Color(0xFFFB8C00),
                      onToggleChanged: (val) => setState(() => _enableA = val),
                      onSliderChanged: (val) => setState(() => _advanceA = val),
                    ),
                    const Divider(height: 1),

                    // 4. L夜班 (LN)
                    _buildFlexibleAlarmSlider(
                      title: 'L夜班 (LN) 智能鬧鐘',
                      startTime: shiftTimes['LN']!,
                      isSubEnabled: _enableLN,
                      currentAdvance: _advanceLN,
                      color: const Color(0xFF00838F),
                      onToggleChanged: (val) => setState(() => _enableLN = val),
                      onSliderChanged: (val) => setState(() => _advanceLN = val),
                    ),
                    const Divider(height: 1),

                    // 5. 夜班 (N)
                    _buildFlexibleAlarmSlider(
                      title: '夜班 (N) 智能鬧鐘',
                      startTime: shiftTimes['N']!,
                      isSubEnabled: _enableN,
                      currentAdvance: _advanceN,
                      color: const Color(0xFF7B1FA2),
                      onToggleChanged: (val) => setState(() => _enableN = val),
                      onSliderChanged: (val) => setState(() => _advanceN = val),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 保存按鈕
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveWidgetSettings,
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text('儲存全彈性設定並即時同步', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
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

  // 📦 核心封裝組件：支援各班次「獨立開關 Toggle」與「大範圍自由調較 Slider」
  Widget _buildFlexibleAlarmSlider({
    required String title,
    required String startTime,
    required bool isSubEnabled,
    required int currentAdvance,
    required Color color,
    required ValueChanged<bool> onToggleChanged,
    required ValueChanged<int> onSliderChanged,
  }) {
    String ringingTime = _calculateAlarmTime(startTime, currentAdvance);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：顏色標誌、名稱、獨立開關
          Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: isSubEnabled,
                  activeColor: color,
                  onChanged: onToggleChanged,
                ),
              ),
            ],
          ),

          // 如果該班次關閉了，變灰顯示已關閉
          if (!isSubEnabled) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                '❌ 本班次鬧鐘已關閉 (當天即使排到此班也不會響鬧)',
                style: TextStyle(color: Colors.red.shade400, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ] else ...[
            // 如果開啟，顯示精準動態減數結果與 Slider
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.between,
              children: [
                Text(
                  currentAdvance == 0 ? '設定：準時出門提示' : '設定：提早 $currentAdvance 分鐘響鬧',
                  style: const TextStyle(fontSize: 13, color: Colors.black80),
                ),
                Text(
                  '🎯 鬧鐘將於 $ringingTime 響起 (開工: $startTime)',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            Slider(
              value: currentAdvance.toDouble(),
              min: 0,
              max: 240, // 0 至 4 小時超寬範圍，揸車或長途車皆可適配
              divisions: 48, // 每 5 分鐘一格，極致精準
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