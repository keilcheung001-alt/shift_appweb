import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/constants.dart';

class WidgetSnapshotWriter {
  static const String _prefix = 'widget_snapshot_';
  static const MethodChannel _channel = MethodChannel('com.example.shift_app/widget');

  static Future<void> writeWidgetSnapshot({
    required String loginGroup,
    required String todayShift,
    required String shiftName,
    required String shiftTime,
    required int leaveCount,
    required List<String> leavers,
    String? nextShift1,
    List<String>? nextShiftLeavers1,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = {
        'todayShift': todayShift,
        'shiftName': shiftName,
        'shiftTime': shiftTime,
        'leaveCount': leaveCount,
        'leavers': leavers,
        'nextShift1': nextShift1 ?? '',
        'nextShiftLeavers1': nextShiftLeavers1 ?? [],
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      final jsonStr = jsonEncode(snapshot);
      await prefs.setString('${_prefix}$loginGroup', jsonStr);
      await prefs.setString('widget_${loginGroup}_data', jsonStr);
      debugPrint('[WidgetSnapshot] ✅ 已寫入 $loginGroup 隊快照, leaveCount=$leaveCount');

      // 主动推送数据到 Android 原生
      await _channel.invokeMethod('updateWidgetData', {
        'team': loginGroup,
        'todayShift': todayShift,
        'shiftName': shiftName,
        'shiftTime': shiftTime,
        'leaveCount': leaveCount,
        'leavers': leavers,
        'nextShift1': nextShift1 ?? '',
        'nextShiftLeavers1': nextShiftLeavers1 ?? [],
      });
      debugPrint('[WidgetSnapshot] ✅ 已推送數據到 Android Widget ($loginGroup)');
    } catch (e) {
      debugPrint('[WidgetSnapshot] ❌ 寫入錯誤: $e');
    }
  }

  static Future<Map<String, dynamic>?> readWidgetSnapshot(String loginGroup) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('${_prefix}$loginGroup');
      return jsonStr == null ? null : jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) { debugPrint('[WidgetSnapshot] ❌ 讀取快照錯誤: $e'); return null; }
  }

  static Future<void> writeAlarmSnapshot({required String staffId, required bool alarmEnabled, required int advanceMinutes, required String? nextAlarmTime}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = {'staffId': staffId, 'alarmEnabled': alarmEnabled, 'advanceMinutes': advanceMinutes, 'nextAlarmTime': nextAlarmTime, 'lastUpdated': DateTime.now().toIso8601String()};
      await prefs.setString('alarm_$staffId', jsonEncode(snapshot));
      debugPrint('[WidgetSnapshot] ✅ 鬧鐘設定已儲存: $staffId');
    } catch (e) { debugPrint('[WidgetSnapshot] ❌ 鬧鐘寫入錯誤: $e'); }
  }

  static Future<Map<String, dynamic>?> readAlarmSnapshot(String staffId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('alarm_$staffId');
      return jsonStr == null ? null : jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) { debugPrint('[WidgetSnapshot] ❌ 讀取鬧鐘錯誤: $e'); return null; }
  }

  static Future<void> forceRefreshForTeam(String team) async => _refreshSnapshotForTeam(team);
  static Future<void> _refreshSnapshotForTeam(String team) async {
    try {
      final today = DateTime.now();
      final todayKey = DateFormat('yyyy-MM-dd').format(today);
      final collection = FIRESTORE_LEAVE_COLLECTIONS[team] ?? 'a_team_leave';
      final doc = await FirebaseFirestore.instance.collection(collection).doc(todayKey).get();
      if (doc.exists) {
        final data = doc.data()!;
        final names = (data['names'] as List<dynamic>?)?.cast<String>() ?? [];
        final reasons = (data['reasons'] as List<dynamic>?)?.cast<String>() ?? [];
        final leaversWithNicknames = <String>[];
        for (int i = 0; i < names.length; i++) {
          final reasonCode = i < reasons.length ? reasons[i].split('-').first : '';
          leaversWithNicknames.add('${names[i]}($reasonCode)');
        }
        final tomorrow = today.add(const Duration(days: 1));
        final nextShift1 = _getShiftForDate(tomorrow, team);
        final tomorrowKey = DateFormat('yyyy-MM-dd').format(tomorrow);
        final tomorrowDoc = await FirebaseFirestore.instance.collection(collection).doc(tomorrowKey).get();
        final tomorrowNames = (tomorrowDoc.data()?['names'] as List<dynamic>?)?.cast<String>() ?? [];
        final tomorrowReasons = (tomorrowDoc.data()?['reasons'] as List<dynamic>?)?.cast<String>() ?? [];
        final tomorrowLeavers = <String>[];
        for (int i = 0; i < tomorrowNames.length; i++) {
          final reasonCode = i < tomorrowReasons.length ? tomorrowReasons[i].split('-').first : '';
          tomorrowLeavers.add('${tomorrowNames[i]}($reasonCode)');
        }
        await writeWidgetSnapshot(loginGroup: team, todayShift: _getShiftForDate(today, team), shiftName: _getShiftName(_getShiftForDate(today, team)), shiftTime: _getShiftTime(_getShiftForDate(today, team)), leaveCount: names.length, leavers: leaversWithNicknames, nextShift1: nextShift1, nextShiftLeavers1: tomorrowLeavers);
      } else {
        await writeWidgetSnapshot(loginGroup: team, todayShift: _getShiftForDate(today, team), shiftName: _getShiftName(_getShiftForDate(today, team)), shiftTime: _getShiftTime(_getShiftForDate(today, team)), leaveCount: 0, leavers: [], nextShift1: _getShiftForDate(today.add(const Duration(days: 1)), team), nextShiftLeavers1: []);
      }
    } catch (e) { debugPrint('[WidgetSnapshot] 刷新 $team 失敗: $e'); }
  }

  static String _getShiftForDate(DateTime date, String team) {
    final cycleStart = DateTime.parse(CYCLE_START_DATE);
    final diff = date.difference(cycleStart).inDays;
    final cycle = TEAM_CYCLES[team] ?? TEAM_CYCLES['A']!;
    return diff < 0 ? '' : cycle[diff % cycle.length];
  }
  static String _getShiftName(String shift) => SHIFT_DISPLAY[shift] ?? shift;
  static String _getShiftTime(String shift) => SHIFT_TIME[shift] ?? '';
  static Future<void> forceRefreshAllWidgets() async { for (final team in ['A','B','C','D']) await _refreshSnapshotForTeam(team); }
}