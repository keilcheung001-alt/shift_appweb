import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/constants.dart';
import '../widgets/leave_edit_dialog.dart';

import '../services/quota_service.dart';
import '../utils/widget_snapshot_writer.dart';
import '../services/leave_delete_service.dart';

class FullCalendarBTeam extends StatefulWidget {
  final String staffId;
  final String teamCode;
  final bool canFullEdit;
  final bool isSuperAdmin;

  const FullCalendarBTeam({
    super.key,
    required this.staffId,
    this.teamCode = 'B',
    required this.canFullEdit,
    required this.isSuperAdmin,
  });

  @override
  State<FullCalendarBTeam> createState() => _FullCalendarBTeamState();
}

class _FullCalendarBTeamState extends State<FullCalendarBTeam> {
  static const String teamCode = 'B';
  static const String bTeamSheetUrlFallback = APPS_SCRIPT_URL_B_TEAM;

  late String bTeamSheetUrl;

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
      debugPrint('B initAll error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadAppScriptUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bTeamSheetUrl = prefs.getString('google_apps_script_url_B') ?? bTeamSheetUrlFallback;
    } catch (e) {
      bTeamSheetUrl = bTeamSheetUrlFallback;
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
      debugPrint('Error loading public holidays (B): $e');
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
      debugPrint('B load custom holidays error: $e');
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
  String dateKey(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String shiftForDate(DateTime date) {
    final d0 = dateOnly(date);
    final diff = d0.difference(dateOnly(cycleStart)).inDays;
    if (diff < 0 || cycle.isEmpty) return '';
    final idx = diff % cycle.length;
    return cycle[idx];
  }

  bool isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  int countPeopleForDate(String dk) {
    final info = teamLeave[dk];
    if (info == null) return 0;
    final names = (info['names'] as List<dynamic>?) ?? [];
    final statuses = (info['statuses'] as List<dynamic>?) ?? [];
    int count = 0;
    for (int i = 0; i < names.length; i++) {
      final status = i < statuses.length ? statuses[i] : 'pending';
      if (status != 'rejected') count++;
    }
    return count;
  }

  Color badgeColorForCount(int count) {
    if (count == 0) return Colors.grey.shade300;
    if (count < warningThreshold) return Colors.grey.shade500;
    if (count < criticalThreshold) return Colors.orange.shade400;
    return Colors.red.shade400;
  }

  Color shiftColor(String shift) {
    switch (shift) {
      case 'M': return Colors.blue.shade300;
      case 'LM': return Colors.blue.shade500;
      case 'A': return Colors.green.shade300;
      case 'N': return Colors.purple.shade300;
      case 'LN': return Colors.indigo.shade300;
      default: return Colors.grey.shade200;
    }
  }

  ({DateTime start, DateTime endExclusive}) visibleRangeForMonthSundayStart(DateTime month) {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final int daysToGoBack = monthStart.weekday == DateTime.sunday ? 0 : monthStart.weekday;
    final visibleStart = dateOnly(monthStart.subtract(Duration(days: daysToGoBack)));
    final int daysToGoForward = monthEnd.weekday == DateTime.sunday ? 6 : DateTime.saturday - monthEnd.weekday;
    final visibleEnd = dateOnly(monthEnd.add(Duration(days: daysToGoForward)));
    final endExclusive = visibleEnd.add(const Duration(days: 1));
    return (start: visibleStart, endExclusive: endExclusive);
  }

  Map<String, Map<String, dynamic>> _snapshotToLeaveMap(QuerySnapshot snap) {
    final leaves = <String, Map<String, dynamic>>{};
    for (final doc in snap.docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final dk = data['dateKey'] ?? doc.id.toString();
        final List<dynamic> names = data['names'] != null ? List<dynamic>.from(data['names']) : <dynamic>[];
        final List<dynamic> nicknames = data['nicknames'] != null ? List<dynamic>.from(data['nicknames']) : <dynamic>[];
        final List<dynamic> reasons = data['reasons'] != null ? List<dynamic>.from(data['reasons']) : <dynamic>[];
        final List<dynamic> statuses = data['statuses'] != null ? List<dynamic>.from(data['statuses']) : <dynamic>[];
        final List<dynamic> compHours = data['compHours'] != null ? List<dynamic>.from(data['compHours']) : <dynamic>[];
        while (nicknames.length < names.length) nicknames.add('');
        while (reasons.length < names.length) reasons.add('');
        while (statuses.length < names.length) statuses.add('pending');
        while (compHours.length < names.length) compHours.add(0.0);
        leaves[dk] = {
          'names': names,
          'nicknames': nicknames,
          'reasons': reasons,
          'statuses': statuses,
          'compHours': compHours,
          'shift': data['shift'] ?? '',
        };
      } catch (e) {
        debugPrint('解析單個文檔失敗 (B): $e');
      }
    }
    return leaves;
  }

  Future<void> subscribeLeavesForVisibleRange() async {
    final range = visibleRangeForMonthSundayStart(currentMonth);
    if (subscribedVisibleStart == range.start && subscribedVisibleEndExclusive == range.endExclusive) return;
    await leaveSub?.cancel();
    leaveSub = null;
    subscribedVisibleStart = range.start;
    subscribedVisibleEndExclusive = range.endExclusive;
    final query = FirebaseFirestore.instance
        .collection(leaveCollection)
        .where('status', whereIn: ['pending', 'approved', 'partial', 'rejected'])
        .where('dateKey', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(range.start))
        .where('dateKey', isLessThan: DateFormat('yyyy-MM-dd').format(range.endExclusive))
        .orderBy('dateKey');
    leaveSub = query.snapshots().listen(
          (snap) {
        if (!mounted) return;
        setState(() {
          teamLeave = _snapshotToLeaveMap(snap);
          loading = false;
        });

        final monthLeaves = <String, List<String>>{};
        teamLeave.forEach((dateKey, info) {
          final names = (info['names'] as List<dynamic>?)?.cast<String>() ?? [];
          final nicknames = (info['nicknames'] as List<dynamic>?)?.cast<String>() ?? [];
          final reasons = (info['reasons'] as List<dynamic>?)?.cast<String>() ?? [];
          final statuses = (info['statuses'] as List<dynamic>?)?.cast<String>() ?? [];
          final formatted = <String>[];
          for (int i = 0; i < names.length; i++) {
            final status = i < statuses.length ? statuses[i] : 'pending';
            if (status == 'rejected') continue;

            String displayName = names[i];
            if (i < nicknames.length && nicknames[i].trim().isNotEmpty) {
              displayName = nicknames[i].trim();
            }
            String leaveType = '';
            if (i < reasons.length && reasons[i].trim().isNotEmpty) {
              final parts = reasons[i].split('-');
              leaveType = parts.first;
            }
            if (leaveType.isNotEmpty) {
              formatted.add('$displayName($leaveType)');
            } else {
              formatted.add(displayName);
            }
          }
          if (formatted.isNotEmpty) {
            monthLeaves[dateKey] = formatted;
          }
        });
        WidgetSnapshotWriter.saveFullMonthLeaves(teamCode, monthLeaves);
      },
      onError: (e) => debugPrint('B Leaves listener error: $e'),
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
      return const Center(child: Text('無請假紀錄', style: TextStyle(fontSize: 14, color: Colors.grey)));
    }

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: monthLeaves.length,
      itemBuilder: (context, index) {
        final entry = monthLeaves[index];
        final info = entry.value;
        final names = (info['names'] as List<dynamic>?)?.cast<String>() ?? const [];
        final nicknames = (info['nicknames'] as List<dynamic>?)?.cast<String>() ?? const [];
        final reasons = (info['reasons'] as List<dynamic>?)?.cast<String>() ?? const [];
        final statuses = (info['statuses'] as List<dynamic>?)?.cast<String>() ?? [];

        final Map<String, Map<String, dynamic>> merged = {};
        for (int i = 0; i < names.length; i++) {
          final status = i < statuses.length ? statuses[i] : 'pending';
          if (status == 'rejected') continue;

          final name = names[i];
          String displayName = name;
          if (i < nicknames.length && nicknames[i].trim().isNotEmpty) {
            displayName = nicknames[i].trim();
          }
          String reason = i < reasons.length ? reasons[i].trim() : '';
          if (reason.isEmpty) continue;

          final parts = reason.split('-');
          final firstType = parts.first;
          final allSame = parts.every((p) => p == firstType);
          final count = parts.length;
          final key = '$displayName|$firstType|$status';
          if (allSame && count > 1) {
            merged[key] = {'name': displayName, 'type': firstType, 'days': count, 'status': status};
          } else {
            merged['$displayName|$reason|$status'] = {'name': displayName, 'type': reason, 'days': 1, 'status': status};
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

        if (pairs.isEmpty) return const SizedBox.shrink();

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

  Future<void> _showAdminDeleteDialog(DateTime day) async {
    final people = LeaveDeleteService.getLeavePeopleForDay(teamLeave, day);
    if (people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('當日無請假記錄')));
      return;
    }

    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🗑️ 管理員刪除請假記錄'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: people.length,
            itemBuilder: (ctx, idx) {
              final p = people[idx];
              final displayName = p['nickname'].toString().isNotEmpty
                  ? '${p['nickname']} (${p['name']})'
                  : p['name'];
              String statusText = '';
              if (p['status'] == 'approved') statusText = '✅ 已批';
              else if (p['status'] == 'pending') statusText = '⏳ 待批';
              else if (p['status'] == 'rejected') statusText = '❌ 已拒';

              return ListTile(
                leading: const Icon(Icons.person, color: Colors.blue),
                title: Text(displayName),
                subtitle: Text(statusText),
                trailing: const Icon(Icons.delete, color: Colors.red),
                onTap: () => Navigator.pop(ctx, idx),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
        ],
      ),
    );

    if (selectedIndex == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除「${people[selectedIndex]['name']}」的請假記錄嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('確認刪除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await LeaveDeleteService.adminForceDelete(
      teamCode: teamCode,
      day: day,
      targetIndex: selectedIndex,
      onRefresh: () => subscribeLeavesForVisibleRange(),
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已刪除該員工請假記錄')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ 刪除失敗'), backgroundColor: Colors.red));
    }
  }

  Future<void> openEditDialog(DateTime day) async {
    final dk = dateKey(day);
    final shift = shiftForDate(day);
    final existing = teamLeave[dk] ?? {};
    final isNormalStaff = !widget.canFullEdit;
    final existingNames = (existing['names'] as List<dynamic>?)?.cast<String>() ?? const [];
    final existingReasons = (existing['reasons'] as List<dynamic>?)?.cast<String>() ?? const [];
    final existingNicknames = (existing['nicknames'] as List<dynamic>?)?.cast<String>() ?? const [];
    final bool alreadyHasMe = existingNames.contains(myName);
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
        onCancelMyPending: () async {
          final success = await LeaveDeleteService.deleteMyLeave(
            teamCode: teamCode,
            myName: myName,
            day: day,
            onSuccess: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已刪除你的請假記錄')),
              );
            },
            onRefresh: () => subscribeLeavesForVisibleRange(),
          );
          if (!success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('無法刪除，請稍後再試'), backgroundColor: Colors.red),
            );
          }
        },
      ),
    );

    if (result == null || result.isCancelled) return;

    // ✅ 已修正：讀取正確的 hours 並轉換為日數
    final deduction = result.deduction;
    if (deduction != null) {
      final compUsed = deduction['compUsed'] as double? ?? 0;
      final alHours = deduction['alHours'] as double? ?? 0;
      final clHours = deduction['clHours'] as double? ?? 0;
      final slHours = deduction['slHours'] as double? ?? 0;
      final personName = deduction['name'] as String? ?? '';

      if (personName == myName && myEmployeeId.isNotEmpty) {
        if (compUsed > 0) {
          await QuotaService.deductCompTime(staffId: myEmployeeId, hours: compUsed);
          debugPrint('✅ 扣減補鐘: $compUsed 小時');
        }
        if (alHours > 0) {
          await QuotaService.deductLeave(staffId: myEmployeeId, leaveType: 'al', days: alHours / 8.0, reason: '請假');
          debugPrint('✅ 扣減 AL: ${alHours / 8.0} 日');
        }
        if (clHours > 0) {
          await QuotaService.deductLeave(staffId: myEmployeeId, leaveType: 'cl', days: clHours / 8.0, reason: '請假');
          debugPrint('✅ 扣減 CL: ${clHours / 8.0} 日');
        }
        if (slHours > 0) {
          await QuotaService.deductLeave(staffId: myEmployeeId, leaveType: 'sl', days: slHours / 8.0, reason: '請假');
          debugPrint('✅ 扣減 SL: ${slHours / 8.0} 日');
        }
      }
    }

    // 然後儲存 Firestore（原本部分不變）
    final col = FirebaseFirestore.instance.collection(leaveCollection);
    for (final entry in result.planByDate.entries) {
      final dateKeyStr = entry.key;
      final payload = entry.value;
      final List<String> newNames = (payload['names'] as List<dynamic>?)
          ?.map((e) => e.toString().trim())
          .where((n) => n.isNotEmpty)
          .toList() ?? [];
      final List<String> newReasons = (payload['reasons'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [];
      final List<String> newNicknames = (payload['nicknames'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [];
      final List<double> newCompHours = (payload['compHours'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList() ?? [];

      if (newNames.isEmpty) continue;

      final docRef = col.doc(dateKeyStr);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snap = await transaction.get(docRef);
        List<String> oldNames = [];
        List<String> oldNicknames = [];
        List<String> oldReasons = [];
        List<String> oldStatuses = [];
        List<String> oldStaffIds = [];
        List<double> oldCompHours = [];

        if (snap.exists) {
          final data = snap.data()!;
          oldNames = List<String>.from(data['names'] ?? []);
          oldNicknames = List<String>.from(data['nicknames'] ?? []);
          oldReasons = List<String>.from(data['reasons'] ?? []);
          oldStatuses = List<String>.from(data['statuses'] ?? []);
          oldStaffIds = List<String>.from(data['staffIds'] ?? []);
          oldCompHours = (data['compHours'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ?? [];
        }

        for (int i = 0; i < newNames.length; i++) {
          final name = newNames[i];
          if (name.isEmpty) continue;
          if (!oldNames.contains(name)) {
            if (oldNames.length < 5) {
              oldNames.add(name);
              oldNicknames.add(i < newNicknames.length ? newNicknames[i] : '');
              oldReasons.add(i < newReasons.length ? newReasons[i] : '');
              oldStatuses.add('pending');
              oldStaffIds.add(name == myName ? myEmployeeId : '');
              oldCompHours.add(i < newCompHours.length ? newCompHours[i] : 0);
            }
          } else {
            final idx = oldNames.indexOf(name);
            if (idx != -1) {
              if (i < newReasons.length && newReasons[i].isNotEmpty) {
                oldReasons[idx] = newReasons[i];
              }
              if (i < newNicknames.length && newNicknames[i].isNotEmpty) {
                oldNicknames[idx] = newNicknames[i];
              }
              if (i < newCompHours.length) {
                oldCompHours[idx] = newCompHours[i];
              }
            }
          }
        }

        while (oldNicknames.length < oldNames.length) oldNicknames.add('');
        while (oldReasons.length < oldNames.length) oldReasons.add('');
        while (oldStatuses.length < oldNames.length) oldStatuses.add('pending');
        while (oldStaffIds.length < oldNames.length) oldStaffIds.add('');
        while (oldCompHours.length < oldNames.length) oldCompHours.add(0);

        final bool hasApproved = oldStatuses.contains('approved');
        final bool hasPending = oldStatuses.contains('pending');
        String overallStatus = 'pending';
        if (hasApproved && !hasPending) {
          overallStatus = 'approved';
        } else if (hasApproved && hasPending) {
          overallStatus = 'partial';
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
            'compHours': oldCompHours,
            'statuses': oldStatuses,
            'status': overallStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    }

    await subscribeLeavesForVisibleRange();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已儲存 ${result.planByDate.length} 天'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final firstDayOfMonth = DateTime(currentMonth.year, currentMonth.month, 1);
    final lastDayOfMonth = DateTime(currentMonth.year, currentMonth.month + 1, 0);
    final int daysBefore = firstDayOfMonth.weekday == DateTime.sunday ? 0 : firstDayOfMonth.weekday;
    final int daysAfter = lastDayOfMonth.weekday == DateTime.sunday ? 6 : DateTime.saturday - lastDayOfMonth.weekday;
    final DateTime calendarStartDate = firstDayOfMonth.subtract(Duration(days: daysBefore));
    final DateTime calendarEndDate = lastDayOfMonth.add(Duration(days: daysAfter));
    final int totalTiles = calendarEndDate.difference(calendarStartDate).inDays + 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('B Team', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: refresh)],
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        constrained: false,
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 1.2,
          height: 3000,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => changeMonth(-1)),
                  Text('${currentMonth.year}-${currentMonth.month}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => changeMonth(1)),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                color: Colors.grey.shade200,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: '日一二三四五六'.split('').map((d) => Expanded(
                    child: Text(d, style: TextStyle(fontWeight: FontWeight.bold, color: d == '日' || d == '六' ? Colors.red : Colors.black87), textAlign: TextAlign.center),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                padding: const EdgeInsets.all(4),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 0.9,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: totalTiles,
                itemBuilder: (context, index) {
                  final day = calendarStartDate.add(Duration(days: index));
                  final bool isNotCurrentMonth = day.month != currentMonth.month;
                  final dk = dateKey(day);
                  final shift = shiftForDate(day);
                  final peopleCount = countPeopleForDate(dk);
                  final badgeColor = badgeColorForCount(peopleCount);
                  final today = DateTime.now();
                  final isPast = day.isBefore(DateTime(today.year, today.month, today.day));
                  final isPublicHoliday = publicHolidays.containsKey(dk);
                  final publicHolidayName = publicHolidays[dk]?['name'] ?? '';
                  final publicHolidayColorValue = publicHolidays[dk]?['color'];
                  final publicHolidayColor = publicHolidayColorValue != null ? Color(publicHolidayColorValue as int) : Colors.red.shade400;
                  final customHolidayData = customHolidays[dk];
                  final isCustomHoliday = customHolidayData != null;
                  final customLabel = customHolidayData?['name'] ?? '';
                  Color cellBg = shiftColor(shift);
                  if (isPast) cellBg = Colors.grey.shade200;
                  if (isPublicHoliday) cellBg = publicHolidayColor.withOpacity(0.2);
                  if (isCustomHoliday) {
                    final colorValue = customHolidayData!['color'] as int?;
                    cellBg = colorValue != null ? Color(colorValue).withOpacity(0.2) : Colors.orange.shade100;
                  }
                  if (isNotCurrentMonth) cellBg = cellBg.withOpacity(0.15);
                  final isToday = isSameDate(day, DateTime.now());
                  return Transform.scale(
                    scale: isToday ? 1.2 : 1.0,
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () => openEditDialog(day),
                      onLongPress: widget.isSuperAdmin ? () => _showAdminDeleteDialog(day) : null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: cellBg,
                          border: Border.all(
                            color: isToday ? Colors.grey.shade800 : (peopleCount > 0 ? badgeColor.withOpacity(0.5) : Colors.grey.shade400),
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
                                        color: isNotCurrentMonth ? Colors.grey.shade400 : (isPast ? Colors.grey.shade600 : Colors.black87),
                                      ),
                                    ),
                                    if (isPublicHoliday) Tooltip(
                                      message: publicHolidayName,
                                      child: Text(' 🇭🇰', style: TextStyle(fontSize: 12, color: publicHolidayColor)),
                                    ),
                                  ],
                                ),
                                Text(
                                  shift,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: isNotCurrentMonth ? Colors.grey.shade400 : (isPast ? Colors.grey.shade500 : Colors.black54),
                                  ),
                                ),
                                if (customLabel.isNotEmpty && !isNotCurrentMonth)
                                  Text(
                                    customLabel.length > 5 ? '${customLabel.substring(0, 5)}…' : customLabel,
                                    style: const TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 2),
                              ],
                            ),
                            if (peopleCount > 0)
                              Positioned(
                                top: -1,
                                right: -1,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: isNotCurrentMonth ? Colors.grey : badgeColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    peopleCount.toString(),
                                    style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
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
              const Divider(height: 1, thickness: 0.5),
              SizedBox(
                height: 600,
                child: buildSummaryList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}