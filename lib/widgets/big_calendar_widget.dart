import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';  // ✅ 新增 Firestore
import 'package:flutter/foundation.dart';               // ✅ 用於 debugPrint

import '../utils/widget_snapshot_writer.dart';
import '../constants/constants.dart';

/// 大日曆Widget - 顯示組別請假情況
class BigCalendarWidget extends StatefulWidget {
  const BigCalendarWidget({super.key});

  @override
  State<BigCalendarWidget> createState() => _BigCalendarWidgetState();
}

class _BigCalendarWidgetState extends State<BigCalendarWidget> {
  String _userTeam = 'A';
  String _userNickname = '';
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  Map<String, Map<String, dynamic>> _monthLeavesByDateKey = {};

  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();

    _refreshTimer = Timer.periodic(const Duration(minutes: 60), (_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // 計算今日班次
  String _getTodayShift(String team) {
    final cycleStart = DateTime.parse(CYCLE_START_DATE);
    final daysDiff = DateTime.now().difference(cycleStart).inDays;
    final cycles = TEAM_CYCLES[team] ?? [];
    if (cycles.isEmpty) return '';
    final idx = daysDiff % cycles.length;
    return cycles[idx];
  }

  String _getShiftDisplay(String shiftCode) {
    return SHIFT_DISPLAY[shiftCode] ?? '休息';
  }

  String _getShiftTime(String shiftCode) {
    return SHIFT_TIME[shiftCode] ?? '';
  }

  // ✅ 直接用 Firestore 查詢
  Future<Map<String, dynamic>> _getLeaveInfo(String team, DateTime date) async {
    try {
      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      final collection = FIRESTORE_LEAVE_COLLECTIONS[team] ?? FIRESTORE_A_TEAM_LEAVE;

      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(dateKey)
          .get();

      if (!doc.exists) {
        return {'hasLeave': false, 'count': 0};
      }

      final data = doc.data()!;
      final names = List<String>.from(data['names'] ?? []);
      final reasons = List<String>.from(data['reasons'] ?? []);
      final nicknames = List<String>.from(data['nicknames'] ?? []);

      return {
        'hasLeave': names.isNotEmpty,
        'count': names.length,
        'nicknames': nicknames.isEmpty ? names : nicknames, // 優先使用 nicknames
        'reasons': reasons,
      };
    } catch (e) {
      debugPrint('獲取請假資料失敗: $e');
      return {'hasLeave': false, 'count': 0};
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();

    _userTeam = (prefs.getString('group') ?? 'A').trim().toUpperCase();
    _userNickname = (prefs.getString('nickName') ?? '').trim();

    final monthStart = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final monthEnd = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final daysInMonth = monthEnd.day;

    final futures = List.generate(daysInMonth, (i) async {
      final date = monthStart.add(Duration(days: i));
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      final leaveInfo = await _getLeaveInfo(_userTeam, date);
      final hasLeave = (leaveInfo['hasLeave'] == true);
      final count = (leaveInfo['count'] ?? 0) as int;

      if (hasLeave && count > 0) {
        return MapEntry<String, Map<String, dynamic>>(dateKey, {
          'date': date,
          'dateKey': dateKey,
          'count': count,
          'nicknames': (leaveInfo['nicknames'] as List?) ?? const [],
          'reasons': (leaveInfo['reasons'] as List?) ?? const [],
        });
      }
      return null;
    });

    final results = await Future.wait(futures);
    final map = <String, Map<String, dynamic>>{};
    for (final r in results) {
      if (r != null) map[r.key] = r.value;
    }

    // 寫入小工具快照
    final today = DateTime.now();
    final todayShift = _getTodayShift(_userTeam);
    final shiftName = _getShiftDisplay(todayShift);
    final shiftTime = _getShiftTime(todayShift);
    final todayKey = DateFormat('yyyy-MM-dd').format(today);
    final todayLeave = map[todayKey];
    final leaveCount = todayLeave?['count'] ?? 0;
    final leavers = (todayLeave?['nicknames'] as List?)?.cast<String>() ?? [];

    await WidgetSnapshotWriter.writeWidgetSnapshot(
      loginGroup: _userTeam,
      todayShift: todayShift,
      shiftName: shiftName,
      shiftTime: shiftTime,
      leaveCount: leaveCount,
      leavers: leavers,
    );

    if (!mounted) return;
    setState(() {
      _monthLeavesByDateKey = map;
      _loading = false;
    });
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
    _loadData();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
    _loadData();
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday;
    final offset = startWeekday - 1;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.2,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        final dayNum = index - offset + 1;
        if (dayNum < 1 || dayNum > daysInMonth) {
          return const SizedBox.shrink();
        }

        final day = DateTime(_currentMonth.year, _currentMonth.month, dayNum);
        final dateKey = DateFormat('yyyy-MM-dd').format(day);

        final leaveInfo = _monthLeavesByDateKey[dateKey];
        final leaveCount = (leaveInfo?['count'] ?? 0) as int;

        final now = DateTime.now();
        final isToday = now.year == day.year && now.month == day.month && now.day == day.day;

        return Container(
          decoration: BoxDecoration(
            color: isToday ? Colors.blue.shade50 : Colors.white,
            border: Border.all(
              color: isToday ? Colors.blue : Colors.grey.shade300,
              width: isToday ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dayNum.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isToday ? Colors.blue : Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              if (leaveCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: leaveCount >= 3
                        ? Colors.red.shade400
                        : leaveCount == 2
                        ? Colors.orange.shade400
                        : Colors.blue.shade400,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$leaveCount人',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeaveSummary() {
    if (_monthLeavesByDateKey.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text(
          '本月沒有請假記錄',
          style: TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    final items = _monthLeavesByDateKey.values.toList()
      ..sort((a, b) => (a['dateKey'] as String).compareTo(b['dateKey'] as String));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('本月請假概要:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        ...items.take(3).map((leave) {
          final dateKey = (leave['dateKey'] ?? '') as String;
          final nicknames = ((leave['nicknames'] as List?) ?? const []).take(2).join(', ');
          final count = (leave['count'] ?? 0) as int;
          final moreCount = count - 2;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$dateKey: $nicknames${moreCount > 0 ? ' 等$moreCount人' : ''}',
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }),
        if (items.length > 3)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              '... 還有${items.length - 3}天有請假',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1), // ✅ 改用 withValues
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade600,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 18, color: Colors.white),
                  onPressed: _previousMonth,
                  padding: EdgeInsets.zero,
                ),
                Column(
                  children: [
                    Text(
                      '$_userTeam 組請假日曆',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      '${_currentMonth.year}年${_currentMonth.month}月'
                          '${_userNickname.isNotEmpty ? '（$_userNickname）' : ''}',
                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 18, color: Colors.white),
                  onPressed: _nextMonth,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.grey.shade100,
            child: Row(
              children: '一二三四五六日'.split('').map((d) {
                return Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: (d == '六' || d == '日') ? Colors.red : Colors.grey.shade700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Padding(padding: const EdgeInsets.all(4), child: _buildCalendarGrid()),
          ),

          Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: _loading ? const Center(child: CircularProgressIndicator()) : _buildLeaveSummary(),
          ),
        ],
      ),
    );
  }
}