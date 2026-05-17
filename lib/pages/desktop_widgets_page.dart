import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

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

  bool _alarmEnabled = true;

  // 👑 我哋傾咗一個鐘頭嘅 5 大班次獨立提前分鐘設定
  int _advanceM = 90;
  int _advanceLM = 90;
  int _advanceA = 60;
  int _advanceLN = 120;
  int _advanceN = 120;

  // 👑 5 大班次獨立鬧鐘開關
  bool _enableM = true;
  bool _enableLM = true;
  bool _enableA = true;
  bool _enableLN = true;
  bool _enableN = true;

  bool _loading = true;

  // 🕒 廠房固定班次開工時間
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
    _loadWidgetSettings();
  }

  Future<void> _loadWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _widgetEnabled = prefs.getBool('widget_enabled') ?? true;
      _selectedTeam = prefs.getString('widget_team') ?? 'A';
      _showNextShift = prefs.getBool('widget_show_next_shift') ?? true;

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
      await alarmChannel.invokeMethod('syncAlarms');
    } catch (e) {
      debugPrint('底層同步跳過');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 桌面小工具與彈性鬧鐘設定儲存成功！')),
      );
    }
  }

  // 自動幫你計返幾點響鬧嘅公式
  String _calculateAlarmTime(String startTimeStr, int earlyMinutes) {
    try {
      final parts = startTimeStr.split(':');
      final int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);

      int totalMins = hour * 60 + minute - earlyMinutes;
      if (totalMins < 0) totalMins += 24 * 60;

      final int finalHour = totalMins ~/ 60;
      final int finalMinute = totalMins % 60;

      return '${finalHour.toString().padLeft(2, '0')}:${finalMinute.toString().padLeft(2, '0')}';
    } catch (e) {
      return startTimeStr;
    }
  }

  // 👑 傾咗一個鐘嘅核心：完美還原帶有 Switch、Slider 相同步計算時間嘅 5 條線 UI 組件
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
            const Padding(padding: EdgeInsets.only(top: 4, bottom: 8), child: Text('❌ 呢個班次嘅鬧鐘閂咗', style: TextStyle(color: Colors.red, fontSize: 12))),
          ] else ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(currentAdvance == 0 ? '設定：準時響' : '設定：提早 $currentAdvance 分鐘響', style: const TextStyle(fontSize: 13, color: Colors.black54)),
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFFFFcf7),
      appBar: AppBar(
        title: const Text('桌面小工具設定', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 桌面小工具狀態
            Card(
              color: const Color(0xFFFFF9F2),
              elevation: 0,
              shape: RoundedRectangleBorder(side: BorderSide(color: Colors.orange.shade100), borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.apps, color: Colors.green),
                        SizedBox(width: 8),
                        Text('桌面小工具狀態', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: _widgetEnabled,
                          activeColor: Colors.green,
                          onChanged: (val) => setState(() => _widgetEnabled = val ?? true),
                        ),
                        const Text('已啟用', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. 選擇顯示隊伍
            const Text('選擇顯示隊伍', style: TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTeam,
                  isExpanded: true,
                  items: ['A', 'B', 'C', 'D'].map((t) => DropdownMenuItem(value: t, child: Text('$t 隊'))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedTeam = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. 顯示內容選項（遵照指示：全盤強制用稱號，多餘開關已斬草除根，絕不給人關閉！）
            const Text('顯示內容選項', style: TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 6),
            Card(
              color: const Color(0xFFFFF9F2),
              elevation: 0,
              shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
              child: CheckboxListTile(
                title: const Text('顯示未來班次 (今日+2日)', style: TextStyle(fontSize: 14)),
                value: _showNextShift,
                activeColor: const Color(0xFF8D6E63),
                onChanged: (val) => setState(() => _showNextShift = val ?? true),
              ),
            ),
            const SizedBox(height: 20),

            // 4. 返工智能鬧鐘（完美保留 5 條完整公式線！花鍋無關功能全部再見）
            const Text('⏰ 廠房班次獨立鬧鐘設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFFFFF9F2),
              elevation: 2,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('開啟返工智能鬧鐘功能', style: TextStyle(fontWeight: FontWeight.bold)),
                    value: _alarmEnabled,
                    activeColor: Colors.orange,
                    onChanged: (val) => setState(() => _alarmEnabled = val),
                  ),
                  if (_alarmEnabled) ...[
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider('早班 (M) 鬧鐘', shiftTimes['M']!, _enableM, _advanceM, const Color(0xFF1E88E5), (val) => setState(() => _enableM = val), (val) => setState(() => _advanceM = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider('L早班 (LM) 鬧鐘', shiftTimes['LM']!, _enableLM, _advanceLM, const Color(0xFF43A047), (val) => setState(() => _enableLM = val), (val) => setState(() => _advanceLM = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider('中班 (A) 鬧鐘', shiftTimes['A']!, _enableA, _advanceA, const Color(0xFFFB8C00), (val) => setState(() => _enableA = val), (val) => setState(() => _advanceA = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider('L夜班 (LN) 鬧鐘', shiftTimes['LN']!, _enableLN, _advanceLN, const Color(0xFF00838F), (val) => setState(() => _enableLN = val), (val) => setState(() => _advanceLN = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider('夜班 (N) 鬧鐘', shiftTimes['N']!, _enableN, _advanceN, const Color(0xFF7B1FA2), (val) => setState(() => _enableN = val), (val) => setState(() => _advanceN = val)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 5. 保存設定
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: _saveWidgetSettings,
                icon: const Icon(Icons.save),
                label: const Text('儲存設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}