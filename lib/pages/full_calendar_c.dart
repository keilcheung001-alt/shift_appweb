import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/constants.dart';
import '../widgets/leave_edit_dialog.dart';
import '../services/google_sheets_service.dart';
import '../utils/widget_snapshot_writer.dart';

class FullCalendarCTeam extends StatefulWidget {
  final String staffId;
  final String teamCode;
  final bool canFullEdit;
  final bool isSuperAdmin;

  const FullCalendarCTeam({
    super.key,
    required this.staffId,
    this.teamCode = 'C',
    required this.canFullEdit,
    required this.isSuperAdmin,
  });

  @override
  State<FullCalendarCTeam> createState() => _FullCalendarCTeamState();
}

class _FullCalendarCTeamState extends State<FullCalendarCTeam> {
  static const String teamCode = 'C';
  static const String cTeamSheetUrlFallback = APPS_SCRIPT_URL_C_TEAM;

  late String cTeamSheetUrl;

  DateTime currentMonth = DateTime.now();
  bool loading = true;

  Map<String, Map<String, dynamic>> teamLeave = {};
  final Map<String, Map<String, dynamic>> customHolidays = {};
  Map<String, Map<String, dynamic>> publicHolidays = {};

  String myName = '';
  String myNickname = '';
  String myEmployeeId = '';
  String myJobTitle = '';

  int warningThreshold = 2;
  int criticalThreshold = 3;

  StreamSubscription<QuerySnapshot>? leaveSub;
  DateTime? subscribedVisibleStart;
  DateTime? subscribedVisibleEndExclusive;

  String get leaveCollection => FIRESTORE_LEAVE_COLLECTIONS[teamCode]!;
  List<String> get cycle => TEAM_CYCLES[teamCode]!;
  DateTime get cycleStart => DateTime.parse(CYCLE_START_DATE);

  @override
  void initState() {
    super.initState();
    initAll();
  }

  @override
  void dispose() {
    leaveSub?.cancel();
    super.dispose();
  }

  Future<void> initAll() async {
    myName = widget.staffId.isNotEmpty ? widget.staffId : '員工';

    try {
      await loadAppScriptUrl();
      await loadPublicHolidays();
      await Future.wait([
        loadMyInfo(),
        loadCustomHolidays(),
        loadThresholds(),
      ]);
      await subscribeLeavesForVisibleRange();
    } catch (e) {
      debugPrint('C initAll error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadAppScriptUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      cTeamSheetUrl = prefs.getString('google_apps_script_url_C') ?? cTeamSheetUrlFallback;
    } catch (e) {
      cTeamSheetUrl = cTeamSheetUrlFallback;
    }
  }

  Future<void> loadPublicHolidays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(SPK_PUBLIC_HOLIDAYS_JSON);
      if (raw != null && raw.trim().isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          publicHolidays = map.cast<String, Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('Error loading public holidays (C): $e');
    }
  }

  Future<void> loadMyInfo() async {
    final prefs = await SharedPreferences.getInstance();
    myName = prefs.getString(SPK_MY_NAME) ?? myName;
    myNickname = prefs.getString(SPK_NICKNAME) ?? '';
    myEmployeeId = prefs.getString(SPK_STAFF_ID) ?? '';
    myJobTitle = prefs.getString(SPK_JOB_TITLE) ?? '';
  }

  Future<void> loadCustomHolidays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(SPK_CUSTOM_HOLIDAYS_JSON);
      if (raw == null || raw.trim().isEmpty) return;

      final map = jsonDecode(raw) as Map<String, dynamic>;
      customHolidays.clear();
      map.forEach((k, v) {
        customHolidays[k] = Map<String, dynamic>.from(v as Map);
      });
    } catch (e) {
      debugPrint('C load custom holidays error: $e');
    }
  }

  Future<void> loadThresholds() async {
    final prefs = await SharedPreferences.getInstance();
    warningThreshold = prefs.getInt('warningThreshold') ?? 2;
    criticalThreshold = prefs.getInt('criticalThreshold') ?? 3;
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    await loadAppScriptUrl();
    await loadPublicHolidays();
    await loadCustomHolidays();
    await loadThresholds();
    await loadMyInfo();
    await subscribeLeavesForVisibleRange();
    if (mounted) setState(() => loading = false);
  }

  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String shiftForDate(DateTime date) {
    final d0 = dateOnly(date);
    final diff = d0.difference(dateOnly(cycleStart)).inDays;
    if (diff < 0 || cycle.isEmpty) return '';
    final idx = diff % cycle.length;
    return cycle[idx];
  }

  bool isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int countPeopleForDate(String dk) =>
      (teamLeave[dk]?['names'] as List<dynamic>?)?.length ?? 0;

  Color badgeColorForCount(int count) {
    if (count == 0) return Colors.grey.shade300;
    if (count < warningThreshold) return Colors.grey.shade500;
    if (count < criticalThreshold) return Colors.orange.shade400;
    return Colors.red.shade400;
  }

  Color shiftColor(String shift) {
    switch (shift) {
      case 'M':
        return Colors.blue.shade300;
      case 'LM':
        return Colors.blue.shade500;
      case 'A':
        return Colors.green.shade300;
      case 'N':
        return Colors.purple.shade300;
      case 'LN':
        return Colors.indigo.shade300;
      default:
        return Colors.grey.shade200;
    }
  }

  ({DateTime start, DateTime endExclusive}) visibleRangeForMonthMondayStart(DateTime month) {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);

    final int daysToGoBack = (monthStart.weekday - DateTime.monday + 7) % 7;
    final visibleStart = dateOnly(monthStart.subtract(Duration(days: daysToGoBack)));

    final int daysToGoForward = (DateTime.sunday - monthEnd.weekday + 7) % 7;
    final visibleEnd = dateOnly(monthEnd.add(Duration(days: daysToGoForward)));

    final endExclusive = visibleEnd.add(const Duration(days: 1));
    return (start: visibleStart, endExclusive: endExclusive);
  }

  Future<void> subscribeLeavesForVisibleRange() async {
    final range = visibleRangeForMonthMondayStart(currentMonth);

    if (subscribedVisibleStart == range.start &&
        subscribedVisibleEndExclusive == range.endExclusive) {
      return;
    }

    await leaveSub?.cancel();
    leaveSub = null;
    subscribedVisibleStart = range.start;
    subscribedVisibleEndExclusive = range.endExclusive;

    final query = FirebaseFirestore.instance
        .collection(leaveCollection)
        .where('status', whereIn: ['pending', 'approved'])
        .where('dateKey', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(range.start))
        .where('dateKey', isLessThan: DateFormat('yyyy-MM-dd').format(range.endExclusive))
        .orderBy('dateKey');

    leaveSub = query.snapshots().listen(
          (snap) {
        if (!mounted) return;
        setState(() {
          teamLeave = snapshotToLeaveMap(snap);
          loading = false;
        });
        _updateWidgetSnapshot();
      },
      onError: (e) => debugPrint('C Leaves listener error: $e'),
    );
  }

  void changeMonth(int delta) async {
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month + delta, 1);
    });
    await subscribeLeavesForVisibleRange();
  }

  // ==================== 底部請假摘要列表 ====================
  Widget buildSummaryList() {
    final monthStart = DateTime(currentMonth.year, currentMonth.month, 1);
    final monthEnd = DateTime(currentMonth.year, currentMonth.month + 1, 0);
    final monthLeaves = teamLeave.entries
        .where((entry) {
      try {
        final date = DateTime.parse(entry.key);
        return !date.isBefore(monthStart) && !date.isAfter(monthEnd);
      } catch (_) {
        return false;
      }
    })
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (monthLeaves.isEmpty) {
      return const Center(
        child: Text('無請假紀錄', style: TextStyle(fontSize: 14, color: Colors.grey)),
      );
    }

    return ListView.builder(
      itemCount: monthLeaves.length,
      itemBuilder: (context, index) {
        final entry = monthLeaves[index];
        final info = entry.value;
        final names = (info['names'] as List<dynamic>?)?.cast<String>() ?? const [];
        final reasons = (info['reasons'] as List<dynamic>?)?.cast<String>() ?? const [];

        // 合併相同類型重複的原因（例如 AL-AL 顯示為 AL x2）
        final Map<String, Map<String, dynamic>> merged = {};
        for (int i = 0; i < names.length; i++) {
          final name = names[i];
          String reason = i < reasons.length ? reasons[i].trim() : '';
          if (reason.isEmpty) continue;

          final parts = reason.split('-');
          final firstType = parts.first;
          final allSame = parts.every((p) => p == firstType);
          final count = parts.length;

          final key = '$name|$firstType';
          if (allSame) {
            merged[key] = {'name': name, 'type': firstType, 'days': count};
          } else {
            merged[key] = {'name': name, 'type': reason, 'days': 1};
          }
        }

        final pairs = merged.values.map((m) {
          final days = m['days'] as int;
          final type = m['type'] as String;
          final name = m['name'] as String;
          if (days > 1) {
            return '$name ($type x$days)';
          } else {
            return '$name ($type)';
          }
        }).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            '${entry.key}: ${pairs.join(', ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        );
      },
    );
  }

  // 取消自己當日的待批請假（只限 pending 狀態）
  Future<void> cancelMyPendingLeaveForDay(DateTime day) async {
    if (myName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未設定姓名，無法取消請假')),
      );
      return;
    }

    final dk = dateKey(day);
    final col = FirebaseFirestore.instance.collection(leaveCollection);
    final docRef = col.doc(dk);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) return;

      final data = snap.data() as Map<String, dynamic>;
      if (data['status'] != 'pending') return;

      final namesDyn = (data['names'] as List<dynamic>? ?? []);
      final reasonsDyn = (data['reasons'] as List<dynamic>? ?? []);

      final names = List<String>.from(namesDyn.map((e) => e.toString().trim()));
      final reasons = List<String>.from(reasonsDyn.map((e) => e.toString().trim()));

      final idx = names.indexWhere((n) => n.trim().toLowerCase() == myName.trim().toLowerCase());
      if (idx == -1) return;

      names.removeAt(idx);
      if (idx < reasons.length) reasons.removeAt(idx);

      if (names.isEmpty) {
        tx.delete(docRef);
      } else {
        tx.update(docRef, {
          'names': names,
          'reasons': reasons,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    await subscribeLeavesForVisibleRange();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已取消你當日嘅待批假期')),
    );
  }

  // ==================== 修正後的 openEditDialog ====================
  // 點擊日期時彈出請假編輯對話框，需要正確顯示已有請假人名
  Future<void> openEditDialog(DateTime day) async {
    final dk = dateKey(day);
    final shift = shiftForDate(day);
    final existing = teamLeave[dk] ?? {};

    final isNormalStaff = !widget.canFullEdit;

    // 讀取當日已儲存的請假資料
    final existingNames = (existing['names'] as List<dynamic>?)?.cast<String>() ?? const [];
    final existingReasons = (existing['reasons'] as List<dynamic>?)?.cast<String>() ?? const [];

    // ✅ 修正：直接根據現有資料初始化表格，不依賴權限判斷來隱藏已有的人名
    final initNames = List<String>.generate(5, (i) {
      // 優先顯示已儲存的人名
      if (i < existingNames.length) {
        return existingNames[i];
      }
      // 第一行空白時，若為普通員工且已登入，預填自己個名方便請假
      else if (i == 0 && myName.isNotEmpty && isNormalStaff) {
        return myName;
      }
      return '';
    });

    final initReasons = List<String>.generate(5, (i) {
      // 優先顯示已儲存的原因
      if (i < existingReasons.length) {
        return existingReasons[i];
      }
      return '';
    });

    final initDays = List<int>.filled(5, 1);

    final result = await showDialog<LeaveEditDialogResult>(
      context: context,
      builder: (context) => LeaveEditDialog(
        day: day,
        shift: shift,
        initNames: initNames,
        initReasons: initReasons,
        initDays: initDays,
        myName: myName,
        myNickname: myNickname,
        publicHolidays: publicHolidays.keys.toSet(),
        cycle: cycle,
        cycleStart: cycleStart,
        onCancelMyPending: () => cancelMyPendingLeaveForDay(day),
      ),
    );

    if (result == null || result.isCancelled) return;

    Map<String, Map<String, dynamic>> sanitizedPlanByDate = {};

    // 普通員工只能提交自己的請假，過濾掉其他人
    if (isNormalStaff) {
      result.planByDate.forEach((dateKeyStr, payload) {
        final names = (payload['names'] as List<dynamic>? ?? [])
            .map((e) => e.toString().trim())
            .toList();
        final reasons = (payload['reasons'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final days = (payload['days'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [];

        final onlyMe = <String>[];
        final onlyReasons = <String>[];
        final onlyDays = <int>[];

        for (int i = 0; i < names.length; i++) {
          if (names[i] == myName) {
            onlyMe.add(myName);
            onlyReasons.add(i < reasons.length ? reasons[i] : '');
            onlyDays.add(i < days.length ? days[i] : 1);
            break;
          }
        }

        if (onlyMe.isNotEmpty) {
          sanitizedPlanByDate[dateKeyStr] = {
            'names': onlyMe,
            'reasons': onlyReasons,
            'days': onlyDays,
          };
        }
      });
    } else {
      sanitizedPlanByDate = result.planByDate;
    }

    if (sanitizedPlanByDate.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('你未有提交任何請假（或者只改咗其他人）'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final col = FirebaseFirestore.instance.collection(leaveCollection);

    for (final entry in sanitizedPlanByDate.entries) {
      final dateKeyStr = entry.key;
      final newNames = List<String>.from(entry.value['names'] as List<dynamic>);
      final newReasons = List<String>.from(entry.value['reasons'] as List<dynamic>);
      final newDays = (entry.value['days'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [];
      final docRef = col.doc(dateKeyStr);

      List<String> finalNames = [];
      List<String> finalReasonsList = [];
      List<String> finalStaffIds = [];

      await FirebaseFirestore.instance.runTransaction<void>((tx) async {
        final snap = await tx.get(docRef);
        final existingData = snap.data() ?? {};
        final oldNames = List<String>.from(
            (existingData['names'] as List<dynamic>? ?? []).map((e) => e.toString()));
        final oldReasons = List<String>.from(
            (existingData['reasons'] as List<dynamic>? ?? []).map((e) => e.toString()));
        final oldStaffIds = List<String>.from(
            (existingData['staffIds'] as List<dynamic>? ?? []).map((e) => e.toString()));

        finalNames.clear();
        finalReasonsList.clear();
        finalStaffIds.clear();
        final seen = <String>{};

        for (int i = 0; i < newNames.length; i++) {
          final n = newNames[i].trim();
          if (n.isEmpty) continue;
          if (seen.add(n)) {
            finalNames.add(n);
            finalReasonsList.add(i < newReasons.length ? newReasons[i] : '');
            if (n == myName) {
              finalStaffIds.add(myEmployeeId);
            } else {
              finalStaffIds.add('');
            }
          }
        }

        for (int i = 0; i < oldNames.length; i++) {
          if (i >= oldReasons.length) continue;
          final n = oldNames[i].trim();
          if (n.isEmpty) continue;
          if (seen.add(n)) {
            finalNames.add(n);
            finalReasonsList.add(oldReasons[i]);
            if (i < oldStaffIds.length) {
              finalStaffIds.add(oldStaffIds[i]);
            } else {
              finalStaffIds.add('');
            }
          }
        }

        tx.set(
          docRef,
          {
            'dateKey': dateKeyStr,
            'date': Timestamp.fromDate(DateTime.parse(dateKeyStr)),
            'shift': shiftForDate(DateTime.parse(dateKeyStr)),
            'names': finalNames,
            'reasons': finalReasonsList,
            'staffIds': finalStaffIds,
            'status': 'pending',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      for (int i = 0; i < finalNames.length; i++) {
        final person = finalNames[i];
        final reason = i < finalReasonsList.length ? finalReasonsList[i] : '';
        final int days = i < newDays.length ? newDays[i] : 1;
        final bool isSelf = person == myName;

        await GoogleSheetsService.uploadLeaveRecord(
          team: widget.teamCode,
          userName: person,
          nickname: isSelf ? myNickname : '',
          employeeId: isSelf ? myEmployeeId : '',
          positionCode: isSelf ? myJobTitle : '',
          dateKey: dateKeyStr,
          reason: reason,
          days: days,
          status: 'pending',
        );
      }
    }

    await subscribeLeavesForVisibleRange();
    await _updateWidgetSnapshot();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已儲存 ${sanitizedPlanByDate.length} 天'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // 更新桌面小工具的快照資料
  Future<void> _updateWidgetSnapshot() async {
    final today = DateTime.now();
    final todayKey = dateKey(today);
    final todayLeave = teamLeave[todayKey];
    final leaveCount = (todayLeave?['names'] as List?)?.length ?? 0;
    final leavers = (todayLeave?['names'] as List?)?.cast<String>() ?? [];

    String shift = '';
    if (todayLeave != null && todayLeave.containsKey('shift')) {
      shift = todayLeave['shift'] as String? ?? '';
    }
    if (shift.isEmpty) {
      shift = shiftForDate(today);
    }

    final shiftDisplay = SHIFT_DISPLAY[shift] ?? shift;
    final shiftHour = SHIFT_START_HOURS[shift];
    final shiftTime = shiftHour != null ? '$shiftHour:00' : '';

    final tomorrow = today.add(const Duration(days: 1));
    final tomorrowKey = dateKey(tomorrow);
    final tomorrowLeave = teamLeave[tomorrowKey];
    String nextShift1 = '';
    if (tomorrowLeave != null && tomorrowLeave.containsKey('shift')) {
      nextShift1 = tomorrowLeave['shift'] as String? ?? '';
    }
    if (nextShift1.isEmpty) {
      nextShift1 = shiftForDate(tomorrow);
    }
    final nextLeavers1 = (tomorrowLeave?['names'] as List?)?.cast<String>() ?? [];

    await WidgetSnapshotWriter.writeWidgetSnapshot(
      loginGroup: widget.teamCode,
      todayShift: shift,
      shiftName: shiftDisplay,
      shiftTime: shiftTime,
      leaveCount: leaveCount,
      leavers: leavers,
      nextShift1: nextShift1,
      nextShiftLeavers1: nextLeavers1,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final daysInMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1)
        .difference(firstDay)
        .inDays;
    final startWeekday = firstDay.weekday % 7;

    return Scaffold(
      appBar: AppBar(
        title: const Text('C Team', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.orange.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: refresh),
        ],
      ),
      body: Column(
        children: [
          // 星期標題列
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            color: Colors.grey.shade200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: '日一二三四五六'
                  .split('')
                  .map(
                    (d) => Expanded(
                  child: Text(
                    d,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: d == '日' || d == '六' ? Colors.red : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          // 月份切換
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => changeMonth(-1)),
              Text(
                '${currentMonth.year}-${currentMonth.month}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => changeMonth(1)),
            ],
          ),
          const SizedBox(height: 8),
          // 日曆網格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.52,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: daysInMonth + startWeekday,
              itemBuilder: (context, index) {
                if (index < startWeekday) return const SizedBox.shrink();
                final dayIndex = index - startWeekday;
                final day = firstDay.add(Duration(days: dayIndex));
                final dk = dateKey(day);
                final shift = shiftForDate(day);
                final peopleCount = countPeopleForDate(dk);
                final badgeColor = badgeColorForCount(peopleCount);

                final today = DateTime.now();
                final isPast = day.isBefore(DateTime(today.year, today.month, today.day));

                final isPublicHoliday = publicHolidays.containsKey(dk);
                final publicHolidayName = publicHolidays[dk]?['name'] ?? '';
                final publicHolidayColorValue = publicHolidays[dk]?['color'];
                final publicHolidayColor = publicHolidayColorValue != null
                    ? Color(publicHolidayColorValue as int)
                    : Colors.red.shade400;
                final customHolidayData = customHolidays[dk];
                final isCustomHoliday = customHolidayData != null;
                final customLabel = customHolidayData?['name'] ?? '';

                Color cellBg = shiftColor(shift);
                if (isPast) cellBg = Colors.grey.shade200;
                if (isPublicHoliday) {
                  cellBg = publicHolidayColor.withOpacity(0.2);
                }
                if (isCustomHoliday) {
                  final colorValue = customHolidayData!['color'] as int?;
                  if (colorValue != null) {
                    cellBg = Color(colorValue).withOpacity(0.2);
                  } else {
                    cellBg = Colors.orange.shade100;
                  }
                }

                final isToday = isSameDate(day, DateTime.now());

                return Transform.scale(
                  scale: isToday ? 1.2 : 1.0,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () => openEditDialog(day),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cellBg,
                        border: Border.all(
                          color: isToday
                              ? Colors.grey.shade800
                              : (peopleCount > 0
                              ? badgeColor.withOpacity(0.5)
                              : Colors.grey.shade400),
                          width: isToday ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    day.day.toString(),
                                    style: TextStyle(
                                      fontSize: isToday ? 14 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: isPast ? Colors.grey.shade600 : Colors.black87,
                                    ),
                                  ),
                                  if (isPublicHoliday)
                                    Tooltip(
                                      message: publicHolidayName,
                                      child: Text(
                                        ' 🇭🇰',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: publicHolidayColor,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                shift,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: isPast ? Colors.grey.shade500 : Colors.black54,
                                ),
                              ),
                              if (customLabel.isNotEmpty)
                                Text(
                                  customLabel.length > 5
                                      ? '${customLabel.substring(0, 5)}…'
                                      : customLabel,
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: Colors.black,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          if (peopleCount > 0)
                            Positioned(
                              top: -1,
                              right: -1,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: badgeColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  peopleCount.toString(),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 底部請假摘要列表
          Container(
            height: 160,
            padding: const EdgeInsets.all(8),
            child: buildSummaryList(),
          ),
        ],
      ),
    );
  }
}

// 將 Firestore 查詢結果轉換為 teamLeave 的 Map
Map<String, Map<String, dynamic>> snapshotToLeaveMap(QuerySnapshot snap) {
  final leaves = <String, Map<String, dynamic>>{};
  for (final doc in snap.docs) {
    final data = doc.data() as Map<String, dynamic>;
    final dk = data['dateKey'] ?? doc.id.toString();
    leaves[dk] = {
      'names': List<dynamic>.from(data['names'] ?? []),
      'reasons': List<dynamic>.from(data['reasons'] ?? []),
      'shift': data['shift'] ?? '',
    };
  }
  return leaves;
}