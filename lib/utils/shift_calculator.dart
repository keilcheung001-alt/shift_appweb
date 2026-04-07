// lib/utils/shift_calculator.dart - 完整無錯版
import 'package:flutter/material.dart';
import '../constants/constants.dart';   // ⬅️ 加入這行引入常量

class ShiftCalculator {
  //  28日循環：各隊班次表（constants.dart TEAM_CYCLES 對應）
  static const Map<String, List<String>> teamCycles = {
    'A': ['', '', 'M', 'M', 'A', 'A', 'N', 'LN', 'LN', '', '', 'M', 'M', 'A', '', '', 'N', 'N', '', '', 'M', 'LM', 'LM', 'A', 'A', 'N', 'N', ''],
    'B': ['LM', 'LM', 'A', 'A', 'N', 'N', '', '', '', 'M', 'M', 'A', 'A', 'N', 'LN', 'LN', '', '', 'M', 'M', 'A', '', '', 'N', 'N', '', '', 'M'],
    'C': ['', '', 'N', 'N', '', '', 'M', 'LM', 'LM', 'A', 'A', 'N', 'N', '', '', '', 'M', 'M', 'A', 'A', 'N', 'LN', 'LN', '', '', 'M', 'M', 'A'],
    'D': ['LN', 'LN', '', '', 'M', 'M', 'A', '', '', 'N', 'N', '', '', 'M', 'LM', 'LM', 'A', 'A', 'N', 'N', '', '', '', 'M', 'M', 'A', 'A', 'N'],
  };

  // 班次顯示 + 顏色（constants.dart SHIFT_DISPLAY / SHIFT_COLORS 對應）
  static const Map<String, Map<String, dynamic>> shiftConfig = {
    'M': {'name': '早班', 'time': '08:00-16:00', 'color': Color(0xFF1E88E5)},
    'LM': {'name': 'L早班', 'time': '08:00-20:00', 'color': Color(0xFF43A047)},
    'A': {'name': '中班', 'time': '16:00-23:00', 'color': Color(0xFFFB8C00)},
    'N': {'name': '夜班', 'time': '23:00-08:00', 'color': Color(0xFF7B1FA2)},
    'LN': {'name': 'L夜班', 'time': '20:00-08:00', 'color': Color(0xFF00838F)},
    '': {'name': '休息', 'time': '全天休息', 'color': Color(0xFFBDBDBD)},
    'REST': {'name': '休息', 'time': '全天休息', 'color': Color(0xFFBDBDBD)},
  };

  ///  計算指定日期班次
  static String calculateShift(String teamCode, DateTime date, {String cycleStart = CYCLE_START_DATE}) {
    try {
      final cycleList = teamCycles[teamCode] ?? [];
      if (cycleList.isEmpty) return '';

      final cycleStartDate = DateTime.parse(cycleStart);
      final daysSinceStart = date.difference(cycleStartDate).inDays;
      final cycleIndex = (daysSinceStart % DEFAULT_SHIFT_CYCLE_LENGTH) % cycleList.length;

      return cycleList[cycleIndex];
    } catch (e) {
      debugPrint('Shift calc error: $e');
      return '';
    }
  }

  /// 取得班次名稱
  static String getShiftName(String code) => shiftConfig[code]?['name'] ?? '未知';

  /// 取得班次時間
  static String getShiftTime(String code) => shiftConfig[code]?['time'] ?? 'N/A';

  ///  取得班次顏色
  static Color getShiftColor(String code) => shiftConfig[code]?['color'] ?? Colors.grey;

  ///  判斷是否休息日
  static bool isRestDay(String shiftCode) => shiftCode.isEmpty || shiftCode == 'REST';

  ///  取得當月請假總數（給日曆用）
  static int getLeaveCount(List<dynamic> leaves, DateTime month) {
    return leaves.where((leave) =>
    leave['startDate'] != null &&
        _isSameMonth(DateTime.parse(leave['startDate']), month)
    ).length;
  }

  static bool _isSameMonth(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month;
  }
}