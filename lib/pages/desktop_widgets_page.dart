import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/auth_util.dart';
import '../utils/widget_snapshot_writer.dart';
import '../constants/constants.dart';

// 只在非網頁版時定義 MethodChannel，避免 web 編譯錯誤
final MethodChannel alarmChannel = kIsWeb ? MethodChannel('') : MethodChannel('com.example.shift_app/alarm');

class DesktopWidgetsPage extends StatefulWidget {
  const DesktopWidgetsPage({super.key});

  @override
  State<DesktopWidgetsPage> createState() => _DesktopWidgetsPageState();
}

class _DesktopWidgetsPageState extends State<DesktopWidgetsPage> {
  String _selectedTeam = 'A';

  // 鬧鐘核心變數
  bool _alarmEnabled = true;
  int _alarmAdvanceMinutes = 15;
  DateTime? _nextAlarmTime;

  // 5個班次的鬧鐘獨立開關狀態 (預設全部開著 true)
  bool _alarmMEnabled = true;
  bool _alarmAEnabled = true;
  bool _alarmNEnabled = true;
  bool _alarmLMEnabled = true;
  bool _alarmLNEnabled = true;

  Map<String, dynamic>? _cachedData;

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _loadWidgetSettings();
    _loadCachedDataForTeam('A');
    _loadAlarmSettings();
  }

  Future<void> _loadWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final homeGroup = await AuthUtil.getHomeGroup();
    final savedTeam = prefs.getString('widget_team') ?? homeGroup;
    setState(() {
      _selectedTeam = savedTeam;
    });
  }

  Future<void> _loadAlarmSettings() async {
    // 網頁版沒有鬧鐘功能，直接返回
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final staffId = await AuthUtil.getStaffId();
    if (staffId.isEmpty) return;

    setState(() {
      _alarmEnabled = true;
      _alarmAdvanceMinutes = prefs.getInt('alarm_advance_minutes_$staffId') ?? 15;

      _alarmMEnabled = prefs.getBool('alarm_enabled_M_$staffId') ?? true;
      _alarmAEnabled = prefs.getBool('alarm_enabled_A_$staffId') ?? true;
      _alarmNEnabled = prefs.getBool('alarm_enabled_N_$staffId') ?? true;
      _alarmLMEnabled = prefs.getBool('alarm_enabled_LM_$staffId') ?? true;
      _alarmLNEnabled = prefs.getBool('alarm_enabled_LN_$staffId') ?? true;
    });
    await _updateNextAlarmTime();
  }

  bool _isAlarmEnabledForShift(String shiftCode) {
    switch (shiftCode) {
      case 'M': return _alarmMEnabled;
      case 'A': return _alarmAEnabled;
      case 'N': return _alarmNEnabled;
      case 'LM': return _alarmLMEnabled;
      case 'LN': return _alarmLNEnabled;
      default: return false;
    }
  }

  // 檢查請假並找出下一個鬧鐘時間（只在手機版有用）
  Future<DateTime?> _findNextAlarmTime() async {
    // 網頁版沒有鬧鐘
    if (kIsWeb) return null;
    final now = DateTime.now();
    final staffId = await AuthUtil.getStaffId();
    if (staffId.isEmpty) return null;

    String leaveCollection = '${_selectedTeam.toLowerCase()}_team_leave';

    for (int offset = 0; offset < 30; offset++) {
      final date = now.add(Duration(days: offset));
      final shift = _getShiftForDate(date);
      if (shift.isEmpty) continue;

      if (!_isAlarmEnabledForShift(shift)) continue;

      final dateString = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      try {
        final leaveDoc = await FirebaseFirestore.instance
            .collection(leaveCollection)
            .doc(dateString)
            .get();

        if (leaveDoc.exists) {
          final Map<String, dynamic> attendees = leaveDoc.data() ?? {};
          if (attendees.containsKey(staffId)) {
            final userLeaveStatus = attendees[staffId]['status'];
            if (userLeaveStatus == 'approved') {
              debugPrint('🔔 偵測到號碼 $staffId 於 $dateString 請假已核准，自動跳過此日鬧鐘！');
              continue;
            }
          }
        }
      } catch (e) {
        debugPrint('檢查 Firebase 請假出錯: $e');
      }

      final shiftHour = SHIFT_START_HOURS[shift];
      if (shiftHour == null || shiftHour == 0) continue;

      DateTime alarmTime = DateTime(date.year, date.month, date.day, shiftHour, 0, 0)
          .subtract(Duration(minutes: _alarmAdvanceMinutes));

      if (alarmTime.isAfter(now) || alarmTime.isAtSameMomentAs(now)) {
        return alarmTime;
      }
    }
    return null;
  }

  Future<void> _updateNextAlarmTime() async {
    if (kIsWeb || !_alarmEnabled) {
      setState(() => _nextAlarmTime = null);
      return;
    }
    final alarmTime = await _findNextAlarmTime();
    setState(() => _nextAlarmTime = alarmTime);
  }

  Future<void> _loadCachedDataForTeam(String team) async {
    var snapshot = await WidgetSnapshotWriter.readWidgetSnapshot(team);
    if (snapshot == null) {
      await WidgetSnapshotWriter.forceRefreshForTeam(team);
      snapshot = await WidgetSnapshotWriter.readWidgetSnapshot(team);
    }
    if (mounted) {
      setState(() {
        _cachedData = snapshot;
      });
      await _updateNextAlarmTime();
    }
  }

  Future<void> _saveWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final staffId = await AuthUtil.getStaffId();

    await prefs.setString('widget_team', _selectedTeam);

    if (staffId.isNotEmpty && !kIsWeb) {
      await prefs.setInt('alarm_advance_minutes_$staffId', _alarmAdvanceMinutes);

      await prefs.setBool('alarm_enabled_M_$staffId', _alarmMEnabled);
      await prefs.setBool('alarm_enabled_A_$staffId', _alarmAEnabled);
      await prefs.setBool('alarm_enabled_N_$staffId', _alarmNEnabled);
      await prefs.setBool('alarm_enabled_LM_$staffId', _alarmLMEnabled);
      await prefs.setBool('alarm_enabled_LN_$staffId', _alarmLNEnabled);

      await _updateNextAlarmTime();

      await WidgetSnapshotWriter.writeAlarmSnapshot(
        staffId: staffId,
        alarmEnabled: true,
        advanceMinutes: _alarmAdvanceMinutes,
        nextAlarmTime: _nextAlarmTime?.toIso8601String(),
      );
    }

    await _refreshWidgetData();
    if (!kIsWeb) await _scheduleAlarm();

    // --- 加入確認顯示 ---
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('✅ 記錄已儲存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _refreshWidgetData() async {
    await WidgetSnapshotWriter.forceRefreshForTeam(_selectedTeam);
    await _loadCachedDataForTeam(_selectedTeam);
  }

  Future<void> _updateAdvanceMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final staffId = await AuthUtil.getStaffId();

    setState(() {
      _alarmAdvanceMinutes = minutes;
    });

    if (staffId.isNotEmpty && !kIsWeb) {
      await prefs.setInt('alarm_advance_minutes_$staffId', minutes);
    }

    await _updateNextAlarmTime();

    if (!kIsWeb && _alarmEnabled) {
      await _scheduleAlarm();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ 提前 $minutes 分鐘已設定'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Future<void> _scheduleAlarm() async {
    if (kIsWeb) return;
    if (!_alarmEnabled) return;
    final alarmTime = await _findNextAlarmTime();
    if (alarmTime == null) return;

    await alarmChannel.invokeMethod('scheduleAlarm', {
      'team': _selectedTeam,
      'triggerTime': alarmTime.millisecondsSinceEpoch,
    });

    await _updateNextAlarmTime();
  }

  String _getShiftForDate(DateTime date) {
    final cycleStart = DateTime.parse(CYCLE_START_DATE);
    final daysDiff = date.difference(cycleStart).inDays;
    if (daysDiff < 0) return '';
    final cycles = TEAM_CYCLES[_selectedTeam] ?? [];
    if (cycles.isEmpty) return '';
    return cycles[daysDiff % cycles.length];
  }

  Future<void> _sendTestNotification() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🌐 網頁版不支援鬧鐘測試通知')),
      );
      return;
    }
    await alarmChannel.invokeMethod('showAlarm', {'team': _selectedTeam});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('測試通知已發送，請查看通知欄'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('桌面小工具設定'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey.shade50,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.widgets, color: Colors.green),
                    const SizedBox(width: 12),
                    const Text('桌面小工具狀態', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    const Text('✅ 已啟用', style: TextStyle(color: Colors.green)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_cachedData != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📊 最新快照資料', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('今日班次: ${_cachedData!['todayShift'] ?? '?'} (${_cachedData!['shiftName'] ?? '?'})'),
                      Text('請假人數: ${_cachedData!['leaveCount'] ?? 0} 人'),
                      Text('請假同事: ${(_cachedData!['leavers'] as List?)?.join(', ') ?? ''}'),
                      if (_cachedData!['nextShift1'] != null) Text('明日: ${_cachedData!['nextShift1']}'),
                      if (_cachedData!['nextShift2'] != null) Text('後日: ${_cachedData!['nextShift2']}'),
                      Text('最後更新: ${_cachedData!['lastUpdated']?.toString().substring(0, 16) ?? ''}'),
                    ],
                  ),
                ),
              ),
            if (_cachedData != null) const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('選擇顯示隊伍', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButton<String>(
                      value: _selectedTeam,
                      isExpanded: true,
                      items: const ['A', 'B', 'C', 'D']
                          .map((team) => DropdownMenuItem(value: team, child: Text('$team 隊')))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedTeam = value);
                          _loadCachedDataForTeam(value);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⏰ 工作鬧鐘設定', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('選擇需要啟用鬧鐘的班次：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          const SizedBox(height: 4),
                          CheckboxListTile(
                            title: const Text('M 班 (早班)'),
                            value: _alarmMEnabled,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) async {
                              setState(() => _alarmMEnabled = val ?? true);
                              await _updateNextAlarmTime();
                            },
                          ),
                          CheckboxListTile(
                            title: const Text('A 班 (中班)'),
                            value: _alarmAEnabled,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) async {
                              setState(() => _alarmAEnabled = val ?? true);
                              await _updateNextAlarmTime();
                            },
                          ),
                          CheckboxListTile(
                            title: const Text('N 班 (夜班)'),
                            value: _alarmNEnabled,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) async {
                              setState(() => _alarmNEnabled = val ?? true);
                              await _updateNextAlarmTime();
                            },
                          ),
                          CheckboxListTile(
                            title: const Text('LM 班 (長早班)'),
                            value: _alarmLMEnabled,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) async {
                              setState(() => _alarmLMEnabled = val ?? true);
                              await _updateNextAlarmTime();
                            },
                          ),
                          CheckboxListTile(
                            title: const Text('LN 班 (長夜班)'),
                            value: _alarmLNEnabled,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) async {
                              setState(() => _alarmLNEnabled = val ?? true);
                              await _updateNextAlarmTime();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _alarmAdvanceMinutes.toDouble(),
                            min: 5,
                            max: 360,
                            divisions: 71,
                            label: '$_alarmAdvanceMinutes 分鐘',
                            activeColor: Colors.orange,
                            onChanged: (val) {
                              setState(() {
                                _alarmAdvanceMinutes = val.round();
                              });
                            },
                            onChangeEnd: (val) {
                              _updateAdvanceMinutes(val.round());
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            final newVal = (_alarmAdvanceMinutes - 5).clamp(5, 360);
                            _updateAdvanceMinutes(newVal);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            final newVal = (_alarmAdvanceMinutes + 5).clamp(5, 360);
                            _updateAdvanceMinutes(newVal);
                          },
                        ),
                      ],
                    ),
                    Text(
                      '將在已啟用班次開工前 $_alarmAdvanceMinutes 分鐘響鬧鐘',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (_nextAlarmTime != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('下一個鬧鐘 (已自動過濾未啟用及已請假班次)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                            const SizedBox(height: 4),
                            Text(
                              '${_nextAlarmTime!.year}-${_nextAlarmTime!.month.toString().padLeft(2, '0')}-${_nextAlarmTime!.day.toString().padLeft(2, '0')} '
                                  '${_nextAlarmTime!.hour.toString().padLeft(2, '0')}:${_nextAlarmTime!.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _sendTestNotification,
                        icon: const Icon(Icons.notifications_active),
                        label: const Text('📢 測試通知 (直接發送)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _refreshWidgetData,
                icon: const Icon(Icons.refresh),
                label: const Text('🔄 即時刷新 Widget 資料'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveWidgetSettings,
                icon: const Icon(Icons.save),
                label: const Text('保存設定'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
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
                  const Text('ℹ️ 小工具説明', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('• 桌面小工具會顯示今日及未來兩日班次', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 需要在手機桌面添加\"Tempo Leave\" Widget', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 長按手機桌面空白位置 > 加入 Widget', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 鬧鐘會喺已啟用班次開始前提醒你', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 如果關閉了某個班次的開關，系統會自動跳過不設鬧鐘', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 如果請咗假（已核准），兩部手機均會連線雲端自動跳過不響', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}