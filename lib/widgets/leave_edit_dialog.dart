// lib/widgets/leave_edit_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/quota_service.dart';
import '../utils/auth_util.dart';

class LeaveEditDialogResult {
  final bool isCancelled;
  final Map<String, Map<String, dynamic>> planByDate;
  final Map<String, dynamic>? deduction;

  LeaveEditDialogResult({
    required this.isCancelled,
    required this.planByDate,
    this.deduction,
  });
}

class LeaveEditDialog extends StatefulWidget {
  final DateTime day;
  final String shift;
  final List<String> initNames;
  final List<String> initReasons;
  final List<int> initDays;
  final String myName;
  final String myNickname;
  final Set<String> publicHolidays;
  final List<String> cycle;
  final DateTime cycleStart;
  final VoidCallback? onCancelMyPending;

  const LeaveEditDialog({
    super.key,
    required this.day,
    required this.shift,
    required this.initNames,
    required this.initReasons,
    required this.initDays,
    required this.myName,
    required this.myNickname,
    required this.publicHolidays,
    required this.cycle,
    required this.cycleStart,
    this.onCancelMyPending,
  });

  @override
  State<LeaveEditDialog> createState() => LeaveEditDialogState();
}

class LeaveEditDialogState extends State<LeaveEditDialog> {
  static const int rowCount = 5;

  final List<TextEditingController> nameCtrls = List.generate(rowCount, (_) => TextEditingController());
  final List<TextEditingController> reasonCtrls = List.generate(rowCount, (_) => TextEditingController());
  final List<TextEditingController> daysCtrls = List.generate(rowCount, (_) => TextEditingController(text: '1'));
  final List<TextEditingController> hoursCtrls = List.generate(rowCount, (_) => TextEditingController(text: ''));
  final List<bool> useHoursMode = List.generate(rowCount, (_) => false);
  final List<bool> _isSaving = List.generate(rowCount, (_) => false);

  final List<FocusNode> nameFocus = List.generate(rowCount, (_) => FocusNode());
  final List<FocusNode> reasonFocus = List.generate(rowCount, (_) => FocusNode());
  final List<FocusNode> daysFocus = List.generate(rowCount, (_) => FocusNode());

  final List<String> leaveTypes = ['AL', 'CL', 'SL', 'TR', '補鐘', 'CL + 0.5AL', 'CL + 補4'];
  late List<String> typeSelected;

  double _compBalance = 0.0;
  String _staffId = '';

  @override
  void initState() {
    super.initState();
    typeSelected = List<String>.filled(rowCount, leaveTypes.first);
    _loadData();

    for (int i = 0; i < rowCount; i++) {
      if (i < widget.initNames.length) nameCtrls[i].text = widget.initNames[i];
      if (i < widget.initReasons.length) reasonCtrls[i].text = widget.initReasons[i];
      if (i < widget.initDays.length && widget.initDays[i] > 0) daysCtrls[i].text = widget.initDays[i].toString();
    }
  }

  Future<void> _loadData() async {
    _staffId = await AuthUtil.getStaffId();
    _compBalance = await QuotaService.getCompBalance(_staffId);
    setState(() {});
  }

  @override
  void dispose() {
    for (var c in nameCtrls) c.dispose();
    for (var c in reasonCtrls) c.dispose();
    for (var c in daysCtrls) c.dispose();
    for (var c in hoursCtrls) c.dispose();
    for (var f in nameFocus) f.dispose();
    for (var f in reasonFocus) f.dispose();
    for (var f in daysFocus) f.dispose();
    super.dispose();
  }

  String dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String shiftForDate(DateTime date) {
    final d0 = DateTime(date.year, date.month, date.day);
    final base = DateTime(widget.cycleStart.year, widget.cycleStart.month, widget.cycleStart.day);
    final diff = d0.difference(base).inDays;
    if (diff < 0 || widget.cycle.isEmpty) return '';
    return widget.cycle[diff % widget.cycle.length];
  }

  double getWorkHoursForShift(String shift) {
    switch (shift) {
      case 'M': return 8.0;
      case 'LM': return 12.0;
      case 'A': return 7.0;
      case 'N': return 9.0;
      case 'LN': return 12.0;
      default: return 8.0;
    }
  }

  bool _isSpecialCombination(String type) {
    return type == 'CL + 0.5AL' || type == 'CL + 補4';
  }

  Map<String, dynamic> calculateDeduction({
    required bool useHours,
    required String leaveType,
    required double daysInput,
    required double hoursInput,
    required String shift,
    required double workHoursPerDay,
    required double compBalance,
  }) {
    if (leaveType == 'TR') {
      return {'compUsed': 0.0, 'alHours': 0.0, 'clHours': 0.0, 'slHours': 0.0, 'error': null};
    }

    if (leaveType == 'CL + 0.5AL') {
      return {
        'compUsed': 0.0,
        'alHours': 4.0,
        'clHours': 8.0,
        'slHours': 0.0,
        'error': null
      };
    }

    if (leaveType == 'CL + 補4') {
      if (4 > compBalance) {
        return {'compUsed': 0.0, 'alHours': 0.0, 'clHours': 0.0, 'slHours': 0.0, 'error': '補鐘餘額不足 (需要4小時)'};
      }
      return {
        'compUsed': 4.0,
        'alHours': 0.0,
        'clHours': 8.0,
        'slHours': 0.0,
        'error': null
      };
    }

    if (useHours) {
      final requestedHours = hoursInput;

      if (leaveType == '補鐘') {
        if (requestedHours > compBalance) {
          return {'compUsed': 0.0, 'alHours': 0.0, 'clHours': 0.0, 'slHours': 0.0, 'error': '補鐘餘額不足'};
        }
        return {'compUsed': requestedHours, 'alHours': 0.0, 'clHours': 0.0, 'slHours': 0.0, 'error': null};
      }

      if (leaveType == 'AL') {
        return {'compUsed': 0.0, 'alHours': requestedHours, 'clHours': 0.0, 'slHours': 0.0, 'error': null};
      }
      if (leaveType == 'CL') {
        return {'compUsed': 0.0, 'alHours': 0.0, 'clHours': requestedHours, 'slHours': 0.0, 'error': null};
      }
      if (leaveType == 'SL') {
        return {'compUsed': 0.0, 'alHours': 0.0, 'clHours': 0.0, 'slHours': requestedHours, 'error': null};
      }
    }

    if (leaveType == '補鐘') {
      final compNeeded = daysInput * workHoursPerDay;
      if (compNeeded > compBalance) {
        return {'compUsed': 0.0, 'alHours': 0.0, 'clHours': 0.0, 'slHours': 0.0, 'error': '補鐘餘額不足'};
      }
      return {'compUsed': compNeeded, 'alHours': 0.0, 'clHours': 0.0, 'slHours': 0.0, 'error': null};
    }

    if (leaveType == 'AL') {
      double alDays = daysInput;
      if (shift == 'LM' || shift == 'LN') {
        alDays = daysInput * 1.5;
      }
      return {'compUsed': 0.0, 'alHours': alDays * 8.0, 'clHours': 0.0, 'slHours': 0.0, 'error': null};
    }

    if (leaveType == 'CL') {
      double clDays = daysInput;
      double alHours = 0.0;
      if ((shift == 'LM' || shift == 'LN') && daysInput > 0) {
        alHours = daysInput * 0.5 * 8.0;
      }
      return {'compUsed': 0.0, 'alHours': alHours, 'clHours': clDays * 8.0, 'slHours': 0.0, 'error': null};
    }

    if (leaveType == 'SL') {
      return {'compUsed': 0.0, 'alHours': 0.0, 'clHours': 0.0, 'slHours': daysInput * 8.0, 'error': null};
    }

    return {'compUsed': 0.0, 'alHours': 0.0, 'clHours': 0.0, 'slHours': 0.0, 'error': '未知錯誤'};
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 請假失敗'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRow(int row) async {
    if (_isSaving[row]) return;
    setState(() => _isSaving[row] = true);

    try {
      // 🔥 關鍵：重新獲取最新補鐘餘額，避免使用過期數據
      _compBalance = await QuotaService.getCompBalance(_staffId);

      final name = nameCtrls[row].text.trim();
      final reason = reasonCtrls[row].text.trim();
      final type = typeSelected[row];
      final isSpecial = _isSpecialCombination(type);
      final useHours = !isSpecial && useHoursMode[row];

      final shiftToday = shiftForDate(widget.day);
      final workHoursPerDay = getWorkHoursForShift(shiftToday);
      if (workHoursPerDay <= 0) {
        _showError('無效班次，無法請假');
        setState(() => _isSaving[row] = false);
        return;
      }

      double daysInput = 0.0;
      double hoursInput = 0.0;

      if (isSpecial) {
        daysInput = 0.0;
        hoursInput = 0.0;
      } else if (useHours) {
        final hoursText = hoursCtrls[row].text.trim();
        if (hoursText.isEmpty) {
          _showError('請輸入時數（小時）');
          setState(() => _isSaving[row] = false);
          return;
        }
        hoursInput = double.tryParse(hoursText) ?? 0.0;
        if (hoursInput <= 0) {
          _showError('時數必須大於 0');
          setState(() => _isSaving[row] = false);
          return;
        }
        daysInput = 0.0;
      } else {
        final daysText = daysCtrls[row].text.trim();
        if (daysText.isEmpty) {
          _showError('請填寫日數');
          setState(() => _isSaving[row] = false);
          return;
        }
        daysInput = double.tryParse(daysText) ?? 0.0;
        if (daysInput <= 0) {
          _showError('日數必須大於 0');
          setState(() => _isSaving[row] = false);
          return;
        }
        hoursInput = 0.0;
      }

      if (name.isEmpty) {
        _showError('請填寫姓名');
        setState(() => _isSaving[row] = false);
        return;
      }
      if (reason.isEmpty && !isSpecial) {
        _showError('請填寫原因');
        setState(() => _isSaving[row] = false);
        return;
      }

      if (type == 'AL' && shiftToday.isEmpty) {
        _showError('當天休息日，不能請 AL');
        setState(() => _isSaving[row] = false);
        return;
      }

      final calc = calculateDeduction(
        useHours: useHours,
        leaveType: type,
        daysInput: daysInput,
        hoursInput: hoursInput,
        shift: shiftToday,
        workHoursPerDay: workHoursPerDay,
        compBalance: _compBalance,
      );

      if (calc['error'] != null) {
        _showError(calc['error']);
        setState(() => _isSaving[row] = false);
        return;
      }

      final totalCompUsed = calc['compUsed'] as double;
      final totalALHours = calc['alHours'] as double;
      final totalCLHours = calc['clHours'] as double;
      final totalSLHours = calc['slHours'] as double;

      final Map<String, Map<String, dynamic>> planByDate = {};

      if (isSpecial) {
        final dk = dateKey(widget.day);
        planByDate[dk] = {
          'names': <String>[name],
          'nicknames': <String>[name == widget.myName ? widget.myNickname : ''],
          'reasons': <String>[type],
          'compHours': <double>[totalCompUsed],
          'alHours': <double>[totalALHours],
          'clHours': <double>[totalCLHours],
          'slHours': <double>[totalSLHours],
          'shifts': <String>[shiftToday],
          'leaveTypes': <String>[type],
        };
      } else if (useHours) {
        final dk = dateKey(widget.day);
        planByDate[dk] = {
          'names': <String>[name],
          'nicknames': <String>[name == widget.myName ? widget.myNickname : ''],
          'reasons': <String>[reason],
          'compHours': <double>[type == '補鐘' ? hoursInput : 0.0],
          'alHours': <double>[type == 'AL' ? hoursInput : 0.0],
          'clHours': <double>[type == 'CL' ? hoursInput : 0.0],
          'slHours': <double>[type == 'SL' ? hoursInput : 0.0],
          'shifts': <String>[shiftToday],
          'leaveTypes': <String>[type],
        };
      } else {
        int daysInt = daysInput.toInt();
        int used = 0, offset = 0;
        while (used < daysInt) {
          final target = widget.day.add(Duration(days: offset++));
          final shift = shiftForDate(target);
          if (type == 'AL' && shift.isEmpty) continue;
          final dk = dateKey(target);
          final targetWorkHours = getWorkHoursForShift(shift);
          if (!planByDate.containsKey(dk)) {
            planByDate[dk] = {
              'names': <String>[],
              'nicknames': <String>[],
              'reasons': <String>[],
              'compHours': <double>[],
              'alHours': <double>[],
              'clHours': <double>[],
              'slHours': <double>[],
              'shifts': <String>[],
              'leaveTypes': <String>[],
            };
          }
          final dailyCalc = calculateDeduction(
            useHours: false,
            leaveType: type,
            daysInput: 1.0,
            hoursInput: 0.0,
            shift: shift,
            workHoursPerDay: targetWorkHours,
            compBalance: _compBalance,
          );
          planByDate[dk]!['names']!.add(name);
          planByDate[dk]!['nicknames']!.add(name == widget.myName ? widget.myNickname : '');
          planByDate[dk]!['reasons']!.add(reason);
          planByDate[dk]!['compHours']!.add(dailyCalc['compUsed'] ?? 0.0);
          planByDate[dk]!['alHours']!.add(dailyCalc['alHours'] ?? 0.0);
          planByDate[dk]!['clHours']!.add(dailyCalc['clHours'] ?? 0.0);
          planByDate[dk]!['slHours']!.add(dailyCalc['slHours'] ?? 0.0);
          planByDate[dk]!['shifts']!.add(shift);
          planByDate[dk]!['leaveTypes']!.add(type);
          used++;
        }
      }

      if (planByDate.isEmpty) {
        _showError('無效請假（可能係休息日）');
        setState(() => _isSaving[row] = false);
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('請假扣減確認'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('👤 員工: $name'),
                Text('📅 日期: ${DateFormat('yyyy-MM-dd').format(widget.day)}'),
                if (!useHours && !isSpecial && daysInput > 1) Text('📆 共 ${daysInput.toInt()} 日'),
                if (useHours) Text('⏱️ 鐘數模式: $hoursInput 小時'),
                if (isSpecial) Text('📌 組合: $type'),
                const Divider(),
                if (totalCompUsed > 0)
                  Text('💰 扣補鐘: ${totalCompUsed.toStringAsFixed(1)} 小時',
                      style: const TextStyle(color: Colors.purple)),
                if (totalALHours > 0)
                  useHours
                      ? Text('🏖️ 扣 AL: ${totalALHours.toStringAsFixed(1)} 小時',
                      style: const TextStyle(color: Colors.blue))
                      : Text('🏖️ 扣 AL: ${(totalALHours / 8).toStringAsFixed(3)} 日',
                      style: const TextStyle(color: Colors.blue)),
                if (totalCLHours > 0)
                  useHours
                      ? Text('🏢 扣 CL: ${totalCLHours.toStringAsFixed(1)} 小時',
                      style: const TextStyle(color: Colors.orange))
                      : Text('🏢 扣 CL: ${(totalCLHours / 8).toStringAsFixed(3)} 日',
                      style: const TextStyle(color: Colors.orange)),
                if (totalSLHours > 0)
                  useHours
                      ? Text('🤒 扣 SL: ${totalSLHours.toStringAsFixed(1)} 小時',
                      style: const TextStyle(color: Colors.green))
                      : Text('🤒 扣 SL: ${(totalSLHours / 8).toStringAsFixed(3)} 日',
                      style: const TextStyle(color: Colors.green)),
                const SizedBox(height: 8),
                if (isSpecial)
                  Text('💡 組合假已預設扣減，無需額外輸入',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('確認請假'),
            ),
          ],
        ),
      );

      if (confirm != true) {
        setState(() => _isSaving[row] = false);
        return;
      }

      Navigator.of(context).pop(LeaveEditDialogResult(
        isCancelled: false,
        planByDate: planByDate,
        deduction: {
          'compUsed': totalCompUsed,
          'alHours': totalALHours,
          'clHours': totalCLHours,
          'slHours': totalSLHours,
          'name': name,
        },
      ));
    } catch (e) {
      _showError('錯誤: $e');
      setState(() => _isSaving[row] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('${DateFormat('yyyy/M/d').format(widget.day)} - ${widget.shift}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: List.generate(rowCount, (i) {
                    final isSpecial = _isSpecialCombination(typeSelected[i]);
                    final canUseHours = !isSpecial && typeSelected[i] != 'CL';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.blue,
                                child: IconButton(
                                  icon: const Icon(Icons.person, color: Colors.white, size: 18),
                                  padding: EdgeInsets.zero,
                                  onPressed: () {
                                    final toFill = widget.myName.isNotEmpty ? widget.myName : widget.myNickname;
                                    if (toFill.isEmpty) return;
                                    setState(() {
                                      nameCtrls[i].text = toFill;
                                      nameCtrls[i].selection = TextSelection.fromPosition(
                                        TextPosition(offset: toFill.length),
                                      );
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: nameCtrls[i],
                                  focusNode: nameFocus[i],
                                  decoration: const InputDecoration(labelText: '姓名', isDense: true, border: OutlineInputBorder()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  final currentName = nameCtrls[i].text.trim();
                                  if (currentName == widget.myName && widget.onCancelMyPending != null) {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('取消請假'),
                                        content: const Text('確定要取消自己的請假記錄嗎？'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('否')),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('是', style: TextStyle(color: Colors.red))),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      Navigator.of(context).pop(LeaveEditDialogResult(isCancelled: true, planByDate: const {}));
                                      widget.onCancelMyPending!();
                                    }
                                  } else {
                                    setState(() {
                                      nameCtrls[i].clear();
                                      reasonCtrls[i].clear();
                                      daysCtrls[i].text = '1';
                                      hoursCtrls[i].text = '';
                                      useHoursMode[i] = false;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: DropdownButtonFormField<String>(
                                  value: typeSelected[i],
                                  items: leaveTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(() {
                                      typeSelected[i] = v;
                                      if (v == 'AL') reasonCtrls[i].text = 'AL';
                                      else if (v == 'CL') reasonCtrls[i].text = 'CL';
                                      else if (v == 'SL') reasonCtrls[i].text = 'SL';
                                      else if (v == 'TR') reasonCtrls[i].text = 'Training';
                                      else if (v == '補鐘') reasonCtrls[i].text = '補鐘';
                                      else if (v == 'CL + 0.5AL') reasonCtrls[i].text = 'CL + 0.5AL';
                                      else if (v == 'CL + 補4') reasonCtrls[i].text = 'CL + 補4';
                                      if (_isSpecialCombination(v)) {
                                        useHoursMode[i] = false;
                                      }
                                    });
                                  },
                                  decoration: const InputDecoration(labelText: '類型', isDense: true, border: OutlineInputBorder()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: reasonCtrls[i],
                                  focusNode: reasonFocus[i],
                                  enabled: !isSpecial,
                                  decoration: InputDecoration(
                                    labelText: isSpecial ? '原因 (自動)' : '原因',
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                    hintText: isSpecial ? typeSelected[i] : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (!isSpecial)
                                SizedBox(
                                  width: 60,
                                  child: TextField(
                                    controller: daysCtrls[i],
                                    focusNode: daysFocus[i],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.center,
                                    enabled: !useHoursMode[i],
                                    decoration: InputDecoration(
                                      labelText: '日數',
                                      isDense: true,
                                      border: const OutlineInputBorder(),
                                      hintText: useHoursMode[i] ? '自動' : '1',
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(width: 60),
                            ],
                          ),
                          if (!isSpecial) ...[
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  value: useHoursMode[i] && canUseHours,
                                  onChanged: canUseHours
                                      ? (value) {
                                    setState(() {
                                      useHoursMode[i] = value ?? false;
                                      if (!useHoursMode[i]) {
                                        hoursCtrls[i].text = '';
                                      }
                                    });
                                  }
                                      : null,
                                ),
                                Text(
                                  '鐘數模式',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: canUseHours ? Colors.black : Colors.grey,
                                  ),
                                ),
                                if (!canUseHours) ...[
                                  const SizedBox(width: 8),
                                  const Text('(CL 不可用鐘數模式)', style: TextStyle(fontSize: 10, color: Colors.red)),
                                ],
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (useHoursMode[i] && canUseHours)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: Text(
                                            '當前補鐘餘額: ${_compBalance.toStringAsFixed(1)} 小時',
                                            style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      TextField(
                                        controller: hoursCtrls[i],
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        enabled: useHoursMode[i] && canUseHours,
                                        decoration: InputDecoration(
                                          labelText: (useHoursMode[i] && canUseHours) ? '時數 (小時)' : '補鐘時數 (小時)',
                                          hintText: (useHoursMode[i] && canUseHours) ? '例如 2.5' : '',
                                          isDense: true,
                                          border: const OutlineInputBorder(),
                                          suffixText: '小時',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: _isSaving[i]
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.save, color: Colors.white),
                              label: Text(_isSaving[i] ? '儲存中...' : '儲存此行'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSaving[i] ? Colors.grey : Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              onPressed: _isSaving[i] ? null : () => _saveRow(i),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text('關閉', style: TextStyle(color: Colors.red)),
                      onPressed: () {
                        if (mounted) Navigator.of(context).pop(LeaveEditDialogResult(isCancelled: true, planByDate: const {}));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}