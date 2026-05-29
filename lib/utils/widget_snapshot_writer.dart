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

  // 辅助函数：根据 staffId 或 name 获取昵称（保留原样）
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

  // 将请假名单转换为显示名称（优先昵称）—— 保留原样，但内部增加类型
  static Future<List<String>> _convertLeaversToDisplayNames(List<String> leavers, List<String> reasons) async {
    final prefs = await SharedPreferences.getInstance();
    final nickname = prefs.getString(SPK_NICKNAME) ?? '';
    final myName = prefs.getString(SPK_MY_NAME) ?? '';
    final displayName = nickname.isNotEmpty ? nickname : myName;

    final result = <String>[];
    for (int i = 0; i < leavers.length; i++) {
      String name = leavers[i];
      if (leavers.length == 1 && (name == myName || name == nickname)) {
        name = displayName;
      }
      String leaveType = '';
      if (i < reasons.length && reasons[i].trim().isNotEmpty) {
        leaveType = reasons[i].split('-').first;
      }
      result.add(leaveType.isEmpty ? name : '$name($leaveType)');
    }
    return result;
  }

  // 核心函数：写入 Widget 数据（已修改：储存未来30天，包含类型）
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
      // 读取现有的完整数据（如果有），否则新建
      final existingJson = prefs.getString('full_month_leaves_$loginGroup');
      Map<String, List<String>> fullMap = {};
      if (existingJson != null) {
        try {
          fullMap = Map<String, List<String>>.from(jsonDecode(existingJson));
        } catch (_) {}
      }
      // 更新今天和明天
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      fullMap[todayKey] = leavers;
      if (nextShiftLeavers1 != null) {
        final tomorrowKey = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));
        fullMap[tomorrowKey] = nextShiftLeavers1;
      }
      // 补全未来30天（没有数据就放空数组）
      final now = DateTime.now();
      for (int i = 0; i < 30; i++) {
        final date = now.add(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(date);
        if (!fullMap.containsKey(key)) {
          fullMap[key] = [];
        }
      }
      final fullMonthJson = jsonEncode(fullMap);
      await prefs.setString('full_month_leaves_$loginGroup', fullMonthJson);
      debugPrint('[WidgetSnapshot] ✅ 已寫入 $loginGroup 隊請假數據 (共 ${fullMap.length} 天)');

      await prefs.setInt('last_sync_timestamp', DateTime.now().millisecondsSinceEpoch);
      debugPrint('[WidgetSnapshot] ✅ 已更新 last_sync_timestamp');

      if (!kIsWeb) {
        await _channel.invokeMethod('updateWidgetData', {
          'team': loginGroup,
          'fullMonthJson': fullMonthJson,
        });
        debugPrint('[WidgetSnapshot] ✅ 已推送數據到 Android Widget ($loginGroup)');
        await _channel.invokeMethod('forceUpdateWidgets');
        debugPrint('[WidgetSnapshot] ✅ 已觸發所有 Widget 強制刷新');
      } else {
        debugPrint('[WidgetSnapshot] 🌐 偵測到網頁環境，跳過 Android Widget 更新');
      }
    } catch (e) {
      debugPrint('[WidgetSnapshot] ❌ 寫入錯誤: $e');
    }
  }

  // 读取快照（保留原函数）
  static Future<Map<String, dynamic>?> readWidgetSnapshot(String loginGroup) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('${_prefix}$loginGroup');
      return jsonStr == null ? null : jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[WidgetSnapshot] ❌ 讀取快照錯誤: $e');
      return null;
    }
  }

  // 储存一个月的请假数据（日期 -> 请假人名单）—— 保留原函数，但内部调用新逻辑
  static Future<void> saveFullMonthLeaves(String team, Map<String, List<String>> monthLeaves) async {
    // 直接调用 writeWidgetSnapshot 来统一处理补全逻辑？但这里只有 monthLeaves，没有班次信息。
    // 为了简单，直接储存并补全未来30天
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final fullMap = Map<String, List<String>>.from(monthLeaves);
    for (int i = 0; i < 30; i++) {
      final key = DateFormat('yyyy-MM-dd').format(now.add(Duration(days: i)));
      if (!fullMap.containsKey(key)) fullMap[key] = [];
    }
    final jsonStr = jsonEncode(fullMap);
    await prefs.setString('full_month_leaves_$team', jsonStr);
    debugPrint('[WidgetSnapshot] 📅 已儲存 $team 隊一個月請假數據 (${fullMap.length} 天)');
    // 通知 Android 更新
    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('updateWidgetData', {'team': team, 'fullMonthJson': jsonStr});
        await _channel.invokeMethod('forceUpdateWidgets');
      } catch (_) {}
    }
  }

  // 闹钟快照（保留原函数）
  static Future<void> writeAlarmSnapshot({required String staffId, required bool alarmEnabled, required int advanceMinutes, required String? nextAlarmTime}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = {
        'staffId': staffId,
        'alarmEnabled': alarmEnabled,
        'advanceMinutes': advanceMinutes,
        'nextAlarmTime': nextAlarmTime,
        'lastUpdated': DateTime.now().toIso8601String()
      };
      await prefs.setString('alarm_$staffId', jsonEncode(snapshot));
      debugPrint('[WidgetSnapshot] ✅ 鬧鐘設定已儲存: $staffId');
    } catch (e) {
      debugPrint('[WidgetSnapshot] ❌ 鬧鐘寫入錯誤: $e');
    }
  }

  static Future<Map<String, dynamic>?> readAlarmSnapshot(String staffId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('alarm_$staffId');
      return jsonStr == null ? null : jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[WidgetSnapshot] ❌ 讀取鬧鐘錯誤: $e');
      return null;
    }
  }

  // 强制刷新单支队伍
  static Future<void> forceRefreshForTeam(String team) async => _refreshSnapshotForTeam(team);

  static Future<void> _refreshSnapshotForTeam(String team) async {
    try {
      final today = DateTime.now();
      final todayKey = DateFormat('yyyy-MM-dd').format(today);
      final collection = FIRESTORE_LEAVE_COLLECTIONS[team] ?? 'a_team_leave';
      final doc = await FirebaseFirestore.instance.collection(collection).doc(todayKey).get();
      if (doc.exists) {
        final data = doc.data()!;
        final names = List<String>.from(data['names'] ?? []);
        final reasons = List<String>.from(data['reasons'] ?? []);
        final nicknames = List<String>.from(data['nicknames'] ?? []);
        // 转换为带类型的昵称
        final leaversWithType = await _convertLeaversToDisplayNames(names, reasons);
        // 补充昵称修正（如果 nicknames 存在优先用）
        final finalLeavers = <String>[];
        for (int i = 0; i < leaversWithType.length; i++) {
          String display = leaversWithType[i];
          if (i < nicknames.length && nicknames[i].trim().isNotEmpty) {
            // 替换名字部分为昵称，但保留类型括号
            final typeMatch = RegExp(r'\((.+)\)$').firstMatch(display);
            if (typeMatch != null) {
              display = '${nicknames[i].trim()}(${typeMatch.group(1)})';
            } else {
              display = nicknames[i].trim();
            }
          }
          finalLeavers.add(display);
        }
        final tomorrow = today.add(const Duration(days: 1));
        final nextShift1 = _getShiftForDate(tomorrow, team);
        final tomorrowKey = DateFormat('yyyy-MM-dd').format(tomorrow);
        final tomorrowDoc = await FirebaseFirestore.instance.collection(collection).doc(tomorrowKey).get();
        final tomorrowNames = List<String>.from(tomorrowDoc.data()?['names'] ?? []);
        final tomorrowReasons = List<String>.from(tomorrowDoc.data()?['reasons'] ?? []);
        final tomorrowNicknames = List<String>.from(tomorrowDoc.data()?['nicknames'] ?? []);
        final tomorrowLeaversRaw = await _convertLeaversToDisplayNames(tomorrowNames, tomorrowReasons);
        final tomorrowLeavers = <String>[];
        for (int i = 0; i < tomorrowLeaversRaw.length; i++) {
          String display = tomorrowLeaversRaw[i];
          if (i < tomorrowNicknames.length && tomorrowNicknames[i].trim().isNotEmpty) {
            final typeMatch = RegExp(r'\((.+)\)$').firstMatch(display);
            if (typeMatch != null) {
              display = '${tomorrowNicknames[i].trim()}(${typeMatch.group(1)})';
            } else {
              display = tomorrowNicknames[i].trim();
            }
          }
          tomorrowLeavers.add(display);
        }
        await writeWidgetSnapshot(
          loginGroup: team,
          todayShift: _getShiftForDate(today, team),
          shiftName: _getShiftName(_getShiftForDate(today, team)),
          shiftTime: _getShiftTime(_getShiftForDate(today, team)),
          leaveCount: names.length,
          leavers: finalLeavers,
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
    } catch (e) {
      debugPrint('[WidgetSnapshot] 刷新 $team 失敗: $e');
    }
  }

  static String _getShiftForDate(DateTime date, String team) {
    final cycleStart = DateTime.parse(CYCLE_START_DATE);
    final diff = date.difference(cycleStart).inDays;
    final cycle = TEAM_CYCLES[team] ?? TEAM_CYCLES['A']!;
    return diff < 0 ? '' : cycle[diff % cycle.length];
  }

  static String _getShiftName(String shift) => SHIFT_DISPLAY[shift] ?? shift;
  static String _getShiftTime(String shift) => SHIFT_TIME[shift] ?? '';

  static Future<void> forceRefreshAllWidgets() async {
    for (final team in ['A', 'B', 'C', 'D']) await _refreshSnapshotForTeam(team);
  }
}