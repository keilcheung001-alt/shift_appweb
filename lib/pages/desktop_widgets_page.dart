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
    'M': '06:45',
    'LM': '07:45',
    'A': '14:45',
    'LN': '22:30',
    'N': '22:45',
  };

  @override
  void initState() {
    super.initState();
    _loadWidgetSettings();
  }

  Future<void> _loadWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _widgetEnabled = prefs.getBool('widgetEnabled') ?? true;
      _selectedTeam = prefs.getString('widgetSelectedTeam') ?? 'A';
      _showNextShift = prefs.getBool('widgetShowNextShift') ?? true;
      _alarmEnabled = prefs.getBool('widgetAlarmEnabled') ?? true;

      _advanceM = prefs.getInt('alarmAdvanceM') ?? 90;
      _advanceLM = prefs.getInt('alarmAdvanceLM') ?? 90;
      _advanceA = prefs.getInt('alarmAdvanceA') ?? 60;
      _advanceLN = prefs.getInt('alarmAdvanceLN') ?? 120;
      _advanceN = prefs.getInt('alarmAdvanceN') ?? 120;

      _enableM = prefs.getBool('alarmEnableM') ?? true;
      _enableLM = prefs.getBool('alarmEnableLM') ?? true;
      _enableA = prefs.getBool('alarmEnableA') ?? true;
      _enableLN = prefs.getBool('alarmEnableLN') ?? true;
      _enableN = prefs.getBool('alarmEnableN') ?? true;

      _loading = false;
    });
  }

  Future<void> _saveWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('widgetEnabled', _widgetEnabled);
    await prefs.setString('widgetSelectedTeam', _selectedTeam);
    await prefs.setBool('widgetShowNextShift', _showNextShift);
    await prefs.setBool('widgetAlarmEnabled', _alarmEnabled);

    await prefs.setInt('alarmAdvanceM', _advanceM);
    await prefs.setInt('alarmAdvanceLM', _advanceLM);
    await prefs.setInt('alarmAdvanceA', _advanceA);
    await prefs.setInt('alarmAdvanceLN', _advanceLN);
    await prefs.setInt('alarmAdvanceN', _advanceN);

    await prefs.setBool('alarmEnableM', _enableM);
    await prefs.setBool('alarmEnableLM', _enableLM);
    await prefs.setBool('alarmEnableA', _enableA);
    await prefs.setBool('alarmEnableLN', _enableLN);
    await prefs.setBool('alarmEnableN', _enableN);

    try {
      await alarmChannel.invokeMethod('updateAlarms');
    } catch (e) {
      debugPrint('Failed to invoke native alarm update: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('💾 設定已成功儲存並同步至系統鬧鐘')),
      );
    }
  }

  // 🔔 觸發原生鬧鐘測試邏輯
  Future<void> _triggerAlarmTest() async {
    try {
      await alarmChannel.invokeMethod('testAlarm');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔔 鬧鐘測試訊號已成功發送至 Android 系統！'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 無法觸發鬧鐘測試: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F5),
      appBar: AppBar(
        title: const Text('桌面小工具設定', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFFF59E0B),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 1. 桌面小工具狀態
          Card(
            color: const Color(0xFFFFFAF7),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFF5EBE6)),
            ),
            child: SwitchListTile(
              title: const Text('桌面小工具狀態', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_widgetEnabled ? '已啟用' : '已關閉'),
              value: _widgetEnabled,
              activeColor: Colors.green,
              onChanged: (val) => setState(() => _widgetEnabled = val),
            ),
          ),
          const SizedBox(height: 12),

          // 2. 顯示快照資料卡片 (固定寬度 270 排版)
          Row(
            children: [
              Container(
                width: 270,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFAF7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF5EBE6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.bar_chart, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text('最新快照資料', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('今日班次: ($_selectedTeam)', style: const TextStyle(height: 1.5, fontSize: 15)),
                    const Text('請假人數: 0 人', style: TextStyle(height: 1.5, fontSize: 15)),
                    const Text('請假同事: ', style: TextStyle(height: 1.5, fontSize: 15)),
                    const Text('明日: N', style: TextStyle(height: 1.5, fontSize: 15)),
                    const SizedBox(height: 8),
                    const Text('最後更新: 2026-05-17T21:44', style: TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. 選擇顯示隊伍
          Card(
            color: const Color(0xFFFFFAF7),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFF5EBE6)),
            ),
            child: ListTile(
              title: const Text('選擇顯示隊伍'),
              trailing: DropdownButton<String>(
                value: _selectedTeam,
                items: ['A', 'B', 'C', 'D'].map((t) => DropdownMenuItem(value: t, child: Text('$t 隊'))).toList(),
                onChanged: (val) => setState(() => _selectedTeam = val ?? 'A'),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 4. 智慧鬧鐘設置區塊
          Card(
            color: const Color(0xFFFFFAF7),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFF5EBE6)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('上班自動鬧鐘提醒', style: TextStyle(fontWeight: FontWeight.bold)),
                  value: _alarmEnabled,
                  activeColor: Colors.orange,
                  onChanged: (val) => setState(() => _alarmEnabled = val),
                ),
                if (_alarmEnabled) ...[
                  const Divider(height: 1),
                  _buildFlexibleAlarmSlider('早班 (M) 鬧鐘', shiftTimes['M']!, _enableM, _advanceM, const Color(0xFF3F51B5), (val) => setState(() => _enableM = val), (val) => setState(() => _advanceM = val)),
                  const Divider(height: 1),
                  _buildFlexibleAlarmSlider('L早班 (LM) 鬧鐘', shiftTimes['LM']!, _enableLM, _advanceLM, const Color(0xFF4CAF50), (val) => setState(() => _enableLM = val), (val) => setState(() => _advanceLM = val)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saveWidgetSettings,
              icon: const Icon(Icons.save),
              label: const Text('儲存設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),

          // 🛠️ 新增區塊：系統測試工具
          Card(
            color: const Color(0xFFFFFAF7),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFF5EBE6), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('系統測試工具', style: TextStyle(fontSize: 14, color: Colors.black54)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.alarm_on_rounded, size: 20),
                      label: const Text('觸發鬧鐘測試', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onPressed: _triggerAlarmTest,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlexibleAlarmSlider(
    String label,
    String baseTime,
    bool enabled,
    int advanceMinutes,
    Color themeColor,
    ValueSetter<bool> onEnabledChanged,
    ValueSetter<int> onAdvanceChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.alarm, color: themeColor, size: 20),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 6),
                  Text('($baseTime)', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
              Switch(
                value: enabled,
                activeColor: themeColor,
                onChanged: onEnabledChanged,
              ),
            ],
          ),
          if (enabled) ...[
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: advanceMinutes.toDouble(),
                    min: 0,
                    max: 180,
                    divisions: 36,
                    activeColor: themeColor,
                    inactiveColor: themeColor.withOpacity(0.2),
                    onChanged: (val) => onAdvanceChanged(val.toInt()),
                  ),
                ),
                Text('提前 $advanceMinutes 分鐘', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}