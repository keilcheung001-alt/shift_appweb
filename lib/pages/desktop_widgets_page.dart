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
  // 永遠啟用，唔使開關
  bool _widgetEnabled = true;
  String _selectedTeam = 'A';
  bool _showLeaveCount = true;
  bool _showNextShift = true;
  bool _showNickname = true;

  final List<Map<String, dynamic>> _updateTimes = [
    {'label': '每日3次 (04:30, 12:30, 20:30)', 'minutes': 480},
  ];
  int _selectedUpdateIndex = 0;

  // 鬧鐘永遠啟用
  bool _alarmEnabled = true;
  int _alarmAdvanceMinutes = 15;
  DateTime? _nextAlarmTime;

  Map<String, dynamic>? _cachedData;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _loadWidgetSettings();
    _loadCachedDataForTeam('A');
    _loadAlarmSettings();
    _loadUpdateFrequency();
    _startAutoRefreshTimer();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (!_widgetEnabled) return;
      final prefs = await SharedPreferences.getInstance();
      final times = prefs.getStringList('widget_update_times_$_selectedTeam') ?? [];
      if (times.isEmpty) return;
      final now = DateTime.now();
      final currentTimeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      if (times.contains(currentTimeStr)) {
        debugPrint('⏰ 自動更新於 $currentTimeStr');
        await _refreshWidgetData();
      }
    });
  }

  Future<void> _loadWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final homeGroup = await AuthUtil.getHomeGroup();
    final savedTeam = prefs.getString('widget_team') ?? homeGroup;
    setState(() {
      _selectedTeam = savedTeam;
      // 強制啟用，唔理儲存值
      _widgetEnabled = true;
      _showLeaveCount = prefs.getBool('widget_show_leave_count_${_selectedTeam}') ?? true;
      _showNextShift = prefs.getBool('widget_show_next_shift_${_selectedTeam}') ?? true;
      _showNickname = prefs.getBool('widget_show_nickname_${_selectedTeam}') ?? true;
    });
  }

  Future<void> _loadUpdateFrequency() async {
    if (mounted) setState(() => _selectedUpdateIndex = 0);
  }

  Future<void> _loadAlarmSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final staffId = await AuthUtil.getStaffId();
    if (staffId.isEmpty) return;
    setState(() {
      // 鬧鐘強制啟用
      _alarmEnabled = true;
      _alarmAdvanceMinutes = prefs.getInt('alarm_advance_minutes_$staffId') ?? 15;
    });
    _updateNextAlarmTime();
  }

  DateTime? _findNextAlarmTime() {
    final now = DateTime.now();
    for (int offset = 0; offset < 30; offset++) {
      final date = now.add(Duration(days: offset));
      final shift = _getShiftForDate(date);
      if (shift.isEmpty) continue;
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

  void _updateNextAlarmTime() {
    if (!_alarmEnabled) {
      setState(() => _nextAlarmTime = null);
      return;
    }
    final alarmTime = _findNextAlarmTime();
    setState(() => _nextAlarmTime = alarmTime);
  }

  String _getTodayShift() {
    final today = DateTime.now();
    final cycleStart = DateTime.parse(CYCLE_START_DATE);
    final daysDiff = today.difference(cycleStart).inDays;
    if (daysDiff < 0) return '';
    final cycles = TEAM_CYCLES[_selectedTeam] ?? [];
    if (cycles.isEmpty) return '';
    return cycles[daysDiff % cycles.length];
  }

  Future<void> _loadCachedDataForTeam(String team) async {
    var snapshot = await WidgetSnapshotWriter.readWidgetSnapshot(team);
    if (snapshot == null) {
      await WidgetSnapshotWriter.forceRefreshForTeam(team);
      snapshot = await WidgetSnapshotWriter.readWidgetSnapshot(team);
    }
    if (mounted) setState(() => _cachedData = snapshot);
  }

  Future<void> _saveWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final staffId = await AuthUtil.getStaffId();

    await prefs.setString('widget_team', _selectedTeam);
    // 唔再儲存啟用狀態，因為強制啟用
    await prefs.setBool('widget_show_leave_count_${_selectedTeam}', _showLeaveCount);
    await prefs.setBool('widget_show_next_shift_${_selectedTeam}', _showNextShift);
    await prefs.setBool('widget_show_nickname_${_selectedTeam}', _showNickname);

    List<String> times = ['04:30', '12:30', '20:30'];
    await prefs.setStringList('widget_update_times_${_selectedTeam}', times);

    if (staffId.isNotEmpty) {
      await prefs.setInt('alarm_advance_minutes_$staffId', _alarmAdvanceMinutes);
      await WidgetSnapshotWriter.writeAlarmSnapshot(
        staffId: staffId,
        alarmEnabled: true,
        advanceMinutes: _alarmAdvanceMinutes,
        nextAlarmTime: _nextAlarmTime?.toIso8601String(),
      );
    }

    await _refreshWidgetData();
    await _scheduleAlarm();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 設定已儲存')),
      );
    }
  }

  Future<void> _refreshWidgetData() async {
    await WidgetSnapshotWriter.forceRefreshForTeam(_selectedTeam);
    await _loadCachedDataForTeam(_selectedTeam);
  }

  Future<bool> _checkExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.scheduleExactAlarm.isGranted) return true;
    final status = await Permission.scheduleExactAlarm.request();
    return status.isGranted;
  }

  Future<void> _showPermissionDialog() async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要精確鬧鐘權限'),
        content: const Text(
          '鬧鐘需要精確鬧鐘權限才能準時提醒你。\n\n'
              '請前往「設定」→「應用程式」→ 允許「精確鬧鐘」權限。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('前往設定'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAdvanceMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final staffId = await AuthUtil.getStaffId();

    setState(() {
      _alarmAdvanceMinutes = minutes;
    });

    if (staffId.isNotEmpty) {
      await prefs.setInt('alarm_advance_minutes_$staffId', minutes);
    }

    _updateNextAlarmTime();

    if (_alarmEnabled) {
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
    if (!_alarmEnabled) return;
    final alarmTime = _findNextAlarmTime();
    if (alarmTime == null) return;

    await alarmChannel.invokeMethod('scheduleAlarm', {
      'team': _selectedTeam,
      'triggerTime': alarmTime.millisecondsSinceEpoch,
    });

    debugPrint('⏰ 鬧鐘已排程 (原生 AlarmManager): $alarmTime');
    _updateNextAlarmTime();
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 移除啟用小工具開關，改為顯示已啟用
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

            // 選擇隊伍等設定保持不變
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
                    const Text('顯示內容選項', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: _showNextShift,
                      onChanged: (value) => setState(() => _showNextShift = value ?? true),
                      title: const Text('顯示未來班次 (今日+2日)'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: _showLeaveCount,
                      onChanged: (value) => setState(() => _showLeaveCount = value ?? true),
                      title: const Text('顯示請假人數'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: _showNickname,
                      onChanged: (value) => setState(() => _showNickname = value ?? true),
                      title: const Text('顯示稱號 (唔係全名)'),
                      subtitle: const Text('例如：小明(AL)'),
                      contentPadding: EdgeInsets.zero,
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
                    const Text('🔄 自動更新頻率', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        '📅 每日3次 (04:30, 12:30, 20:30)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '有人更新資料時會自動同步，唔使等',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
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
                    // 移除啟用鬧鐘開關，改為顯示已啟用
                    const Row(
                      children: [
                        Icon(Icons.alarm, color: Colors.green),
                        SizedBox(width: 8),
                        Text('鬧鐘狀態：', style: TextStyle(fontWeight: FontWeight.w500)),
                        Text('✅ 已啟用', style: TextStyle(color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _alarmAdvanceMinutes.toDouble(),
                            min: 5,
                            max: 360,  // ✅ 改為 6 小時（360分鐘）
                            divisions: 71,
                            label: '$_alarmAdvanceMinutes 分鐘',
                            activeColor: Colors.orange,
                            onChanged: (val) {
                              setState(() {
                                _alarmAdvanceMinutes = val.round();
                              });
                              _updateNextAlarmTime();
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
                      '將在班次前 $_alarmAdvanceMinutes 分鐘響鬧鐘',
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
                            const Text('下一個鬧鐘', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
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
                  Text('• 需要在手機桌面添加"Tempo Leave" Widget', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 長按手機桌面空白位置 > 加入 Widget', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 鬧鐘會喺班次開始前提醒你', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                  Text('• 如果請咗假（已核准），當日唔會響鬧鐘', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}