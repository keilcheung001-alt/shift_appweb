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

class FullCalendarATeam extends StatefulWidget {
  final String staffId;
  final String teamCode;
  final bool canFullEdit;
  final bool isSuperAdmin;

  const FullCalendarATeam({
    super.key,
    required this.staffId,
    this.teamCode = 'A',
    required this.canFullEdit,
    required this.isSuperAdmin,
  });

  @override
  State<FullCalendarATeam> createState() => _FullCalendarATeamState();
}

class _FullCalendarATeamState extends State<FullCalendarATeam> {
  static const String teamCode = 'A';
  static const String aTeamSheetUrlFallback = APPS_SCRIPT_URL_A_TEAM;

  late String aTeamSheetUrl;

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
      debugPrint('A initAll error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadAppScriptUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      aTeamSheetUrl = prefs.getString('google_apps_script_url_A') ?? aTeamSheetUrlFallback;
    } catch (e) {
      aTeamSheetUrl = aTeamSheetUrlFallback;
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
      debugPrint('Error loading public holidays (A): $e');
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
      debugPrint('A load custom holidays error: $e');
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

  // ✅ 核心修正：加入 'partial' 監聽條件，分批審批的假絕對不會失蹤！
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
        .where('status', whereIn: ['pending', 'approved', 'partial'])
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
      onError: (e) => debugPrint('A Leaves listener error: $e'),
    );
  }

  void changeMonth(int delta) async {
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month + delta, 1);
    });
    await subscribeLeavesForVisibleRange();
  }

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
        final statuses = (info['statuses'] as List<dynamic>?)?.cast<String>() ?? [];

        final Map<String, Map<String, dynamic>> merged = {};
        for (int i = 0; i < names.length; i++) {
          final name = names[i];
          String reason = i < reasons.length ? reasons[i].trim() : '';
          if (reason.isEmpty) continue;
          final status = i < statuses.length ? statuses[i] : 'pending';

          final parts = reason.split('-');
          final firstType = parts.first;
          final allSame = parts.every((p) => p == firstType);
          final count = parts.length;

          final key = '$name|$firstType|$status';
          if (allSame && count > 1) {
            merged[key] = {'name': name, 'type': firstType, 'days': count, 'status': status};
          } else {
            merged['$name|$reason|$status'] = {'name': name, 'type': reason, 'days': 1, 'status': status};
          }
        }

        final pairs = merged.values.map((m) {
          final days = m['days'] as int;
          final type = m['type'] as String;
          final name = m['name'] as String;
          final status = m['status'] as String;
          final statusIcon = status == 'approved' ? ' ✅' : ' ⏳';
          if (days > 1) {
            return '$name ($type x$days)$statusIcon';
          } else {
            return '$name ($type)$statusIcon';
          }
        }).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            '${entry.key}: ${pairs.join(', ')}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        );
      },
    );
  }

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

      final namesDyn = (data['names'] as List<dynamic>? ?? []);
      final reasonsDyn = (data['reasons'] as List<dynamic>? ?? []);
      final statusesDyn = (data['statuses'] as List<dynamic>? ?? []);
      final nicknamesDyn = (data['nicknames'] as List<dynamic>? ?? []);
      final staffIdsDyn = (data['staffIds'] as List<dynamic>? ?? []);

      final names = List<String>.from(namesDyn.map((e) => e.toString().trim()));
      final reasons = List<String>.from(reasonsDyn.map((e) => e.toString().trim()));
      final statuses = List<String>.from(statusesDyn.map((e) => e.toString().trim()));
      final nicknames = List<String>.from(nicknamesDyn.map((e) => e.toString().trim()));
      final staffIds = List<String>.from(staffIdsDyn.map((e) => e.toString().trim()));

      final idx = names.indexWhere((n) => n.trim().toLowerCase() == myName.trim().toLowerCase());
      if (idx == -1) return;

      // 只能取消自己 pending 狀態的假
      if (idx >= statuses.length || statuses[idx] != 'pending') return;

      names.removeAt(idx);
      if (idx < reasons.length) reasons.removeAt(idx);
      if (idx < statuses.length) statuses.removeAt(idx);
      if (idx < nicknames.length) nicknames.removeAt(idx);
      if (idx < staffIds.length) staffIds.removeAt(idx);

      if (names.isEmpty) {
        tx.delete(docRef);
      } else {
        final bool hasApproved = statuses.contains('approved');
        final bool hasPending = statuses.contains('pending');
        String overallStatus = 'pending';
        if (hasApproved && !hasPending) {
          overallStatus = 'approved';
        } else if (hasApproved && hasPending) {
          overallStatus = 'partial';
        }

        tx.update(docRef, {
          'names': names,
          'reasons': reasons,
          'statuses': statuses,
          'nicknames': nicknames,
          'staffIds': staffIds,
          'status': overallStatus,
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

  // ✅ 終極安全版 openEditDialog：死守 5 人格子，完美無損合併，守護 partial 狀態
  Future<void> openEditDialog(DateTime day) async {
    final dk = dateKey(day);
    final shift = shiftForDate(day);
    final existing = teamLeave[dk] ?? {};

    final isNormalStaff = !widget.canFullEdit;

    final existingNames = (existing['names'] as List<dynamic>?)?.cast<String>() ?? const [];
    final existingReasons = (existing['reasons'] as List<dynamic>?)?.cast<String>() ?? const [];
    final existingNicknames = (existing['nicknames'] as List<dynamic>?)?.cast<String>() ?? const [];

    final bool alreadyHasMe = existingNames.contains(myName);

    // 1. 打開視窗時自動排隊：不與舊人位置重疊，嚴格卡死長度為 5
    final initNames = List<String>.generate(5, (i) {
      if (i < existingNames.length) return existingNames[i];
      else if (!alreadyHasMe && myName.isNotEmpty && isNormalStaff && i == existingNames.length) return myName;
      return '';
    });

    final initReasons = List<String>.generate(5, (i) {
      if (i < existingReasons.length) return existingReasons[i];
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

    final col = FirebaseFirestore.instance.collection(leaveCollection);

    for (final entry in result.planByDate.entries) {
      final dateKeyStr = entry.key;
      final payload = entry.value;

      final List<String> newNames = (payload['names'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((n) => n.isNotEmpty)
              .toList() ??
          [];

      final List<String> newReasons = (payload['reasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      final List<String> newNicknames = (payload['nicknames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      final List<int> newDays = (payload['days'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [];

      if (newNames.isEmpty) continue;

      final docRef = col.doc(dateKeyStr);

      // 2. 核心 Transaction：拿舊數據做無損精準合併
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snap = await transaction.get(docRef);

        List<String> oldNames = [];
        List<String> oldNicknames = [];
        List<String> oldReasons = [];
        List<String> oldStatuses = [];
        List<String> oldStaffIds = [];

        if (snap.exists) {
          final data = snap.data()!;
          oldNames = List<String>.from(data['names'] ?? []);
          oldNicknames = List<String>.from(data['nicknames'] ?? []);
          oldReasons = List<String>.from(data['reasons'] ?? []);
          oldStatuses = List<String>.from(data['statuses'] ?? []);
          oldStaffIds = List<String>.from(data['staffIds'] ?? []);
        }

        // 把新輸入的數據補入舊名單
        for (int i = 0; i < newNames.length; i++) {
          final name = newNames[i];
          if (name.isEmpty) continue;

          if (!oldNames.contains(name)) {
            // 死守最多 5 個人的鐵則，超額直接被拒絕追加！
            if (oldNames.length < 5) {
              oldNames.add(name);
              oldNicknames.add(i < newNicknames.length ? newNicknames[i] : '');
              oldReasons.add(i < newReasons.length ? newReasons[i] : '');
              oldStatuses.add('pending'); // 新加的人一定未批
              oldStaffIds.add(name == myName ? widget.staffId : '');
            }
          } else {
            // 如果原本就在入面，只准更新原因或別名，【絕對不能動】原本老細批完的狀態！
            final idx = oldNames.indexOf(name);
            if (idx != -1 && i < newReasons.length && newReasons[i].isNotEmpty) {
              oldReasons[idx] = newReasons[i];
            }
            if (idx != -1 && i < newNicknames.length && newNicknames[i].isNotEmpty) {
              oldNicknames[idx] = newNicknames[i];
            }
          }
        }

        while (oldNicknames.length < oldNames.length) oldNicknames.add('');
        while (oldReasons.length < oldNames.length) oldReasons.add('');
        while (oldStatuses.length < oldNames.length) oldStatuses.add('pending');
        while (oldStaffIds.length < oldNames.length) oldStaffIds.add('');

        // 3. 精準動態計算法：完美保護並重現 status: "partial"
        final bool hasApproved = oldStatuses.contains('approved');
        final bool hasPending = oldStatuses.contains('pending');

        String overallStatus = 'pending';
        if (hasApproved && !hasPending) {
          overallStatus = 'approved';
        } else if (hasApproved && hasPending) {
          overallStatus = 'partial'; // 有人批咗、有人未批，這就是 partial 追老細的核心！
        }

        transaction.set(
          docRef,
          {
            'dateKey': dateKeyStr,
            'date': Timestamp.fromDate(DateTime.parse(dateKeyStr)),
            'shift': shiftForDate(DateTime.parse(dateKeyStr)),
            'names': oldNames,
            'nicknames': oldNicknames,
            'reasons': oldReasons,
            'staffIds': oldStaffIds,
            'statuses': oldStatuses,
            'status': overallStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      // 同步到 Google Sheet 邏輯
      for (int i = 0; i < newNames.length; i++) {
        final person = newNames[i];
        if (person.isEmpty) continue;
        final reason = i < newReasons.length ? newReasons[i] : '';
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
        content: Text('已儲存 ${result.planByDate.length} 天'),
        backgroundColor: Colors.green,
      ),
    );
  }

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
        title: const Text('A Team', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: refresh),
        ],
      ),
      body: Column(
        children: [
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
          Expanded(
            flex: 4,
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.15,
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

                String displayName = "";
                if (teamLeave.containsKey(dk)) {
                  final data = teamLeave[dk]!;
                  final nicknames = data['nicknames'] as List? ?? [];
                  final names = data['names'] as List? ?? [];
                  if (nicknames.isNotEmpty && nicknames[0].toString().isNotEmpty) {
                    displayName = nicknames[0].toString();
                  } else if (names.isNotEmpty) {
                    displayName = names[0].toString();
                  }
                }

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
                              if (displayName.isNotEmpty)
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.black87,
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
          const Divider(height: 1, thickness: 0.5),
          Expanded(
            flex: 3,
            child: buildSummaryList(),
          ),
        ],
      ),
    );
  }
}

Map<String, Map<String, dynamic>> snapshotToLeaveMap(QuerySnapshot snap) {
  final leaves = <String, Map<String, dynamic>>{};
  for (final doc in snap.docs) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final dk = data['dateKey'] ?? doc.id.toString();

      final List<dynamic> names = data['names'] != null ? List<dynamic>.from(data['names']) : <dynamic>[];
      final List<dynamic> nicknames = data['nicknames'] != null ? List<dynamic>.from(data['nicknames']) : <dynamic>[];
      final List<dynamic> reasons = data['reasons'] != null ? List<dynamic>.from(data['reasons']) : <dynamic>[];
      final List<dynamic> statuses = data['statuses'] != null ? List<dynamic>.from(data['statuses']) : <dynamic>[];

      while (nicknames.length < names.length) nicknames.add("");
      while (reasons.length < names.length) reasons.add("");
      while (statuses.length < names.length) statuses.add("pending");

      leaves[dk] = {
        'names': names,
        'nicknames': nicknames,
        'reasons': reasons,
        'statuses': statuses,
        'shift': data['shift'] ?? '',
      };
    } catch (e) {
      debugPrint('單日解析失敗（已跳過）: $e');
    }
  }
  return leaves;
}