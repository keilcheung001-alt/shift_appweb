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

  // 輔助函數：根據 staffId 或 name 獲取暱稱
  static Future<String> _getNickname(String staffIdOrName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nickname = prefs.getString(SPK_NICKNAME) ?? '';
      final name = prefs.getString(SPK_MY_NAME) ?? '';
      if (nickname.isNotEmpty) return nickname;
      return name;
    } catch (e) {
      return staffIdOrName;
    }
  }

  // 將請假名單轉換為顯示名稱（優先暱稱）
  static Future<List<String>> _convertLeaversToDisplayNames(List<String> leavers) async {
    final prefs = await SharedPreferences.getInstance();
    final nickname = prefs.getString(SPK_NICKNAME) ?? '';
    final myName = prefs.getString(SPK_MY_NAME) ?? '';
    final displayName = nickname.isNotEmpty ? nickname : myName;

    if (leavers.length == 1 && (leavers.first == myName || leavers.first == nickname)) {
      return [displayName];
    }
    return leavers;
  }

  // ✅ 核心函數：寫入 Widget 數據（已修正網頁版相容性）
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

      // 建立 fullMonthJson（包含今日同日）
      final monthLeaves = <String, List<String>>{};
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      monthLeaves[todayKey] = leavers;
      if (nextShiftLeavers1 != null && nextShiftLeavers1.isNotEmpty) {
        final tomorrowKey = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));
        monthLeaves[tomorrowKey] = nextShiftLeavers1;
      }
      final fullMonthJson = jsonEncode(monthLeaves);

      // 寫入本地 SharedPreferences
      await prefs.setString('full_month_leaves_$loginGroup', fullMonthJson);
      debugPrint('[WidgetSnapshot] ✅ 已寫入 $loginGroup 隊請假數據');

      // 寫入 last_sync_timestamp
      await prefs.setInt('last_sync_timestamp', DateTime.now().millisecondsSinceEpoch);
      debugPrint('[WidgetSnapshot] ✅ 已更新 last_sync_timestamp');

      // --- 修正區域：網頁版會在此跳過 Android 功能，不再導致崩潰 ---
      if (!kIsWeb) {
        // 透過 MethodChannel 觸發 Android 端更新所有 Widget
        await _channel.invokeMethod('updateWidgetData', {
          'team': loginGroup,
          'fullMonthJson': fullMonthJson,
        });
        debugPrint('[WidgetSnapshot] ✅ 已推送數據到 Android Widget ($loginGroup)');

        // 強制刷新所有 Widget
        await _channel.invokeMethod('forceUpdateWidgets');
        debugPrint('[WidgetSnapshot] ✅ 已觸發所有 Widget 強制刷新');
      } else {
        debugPrint('[WidgetSnapshot] 🌐 偵測到網頁環境，跳過 Android Widget 更新');
      }
      // ---------------------------------------------------------

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

  // 儲存一個月的請假數據（日期 -> 請假人名單）
  static Future<void> saveFullMonthLeaves(String team, Map<String, List<String>> monthLeaves) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(monthLeaves);
    await prefs.setString('full_month_leaves_$team', jsonStr);
    debugPrint('[WidgetSnapshot] 📅 已儲存 $team 隊一個月請假數據 (${monthLeaves.length} 天)');
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
        await writeWidgetSnapshot(
          loginGroup: team,
          todayShift: _getShiftForDate(today, team),
          shiftName: _getShiftName(_getShiftForDate(today, team)),
          shiftTime: _getShiftTime(_getShiftForDate(today, team)),
          leaveCount: names.length,
          leavers: leaversWithNicknames,
          nextShift1: nextShift1,
          nextShiftLeavers1: tomorrowLeavers,
        );
      } else {
        await writeWidgetSnapshot(
          loginGroup: team,
          todayShift: _getShiftForDate(today, team),
          shiftName: _getShiftName(_getShiftForDate(today, team)),
          shiftTime: _getShiftTime(_getShiftForDate(today, team)),
          leaveCount: 0,
          leavers: [],
          nextShift1: _getShiftForDate(today.add(const Duration(days: 1)), team),
          nextShiftLeavers1: [],
        );
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