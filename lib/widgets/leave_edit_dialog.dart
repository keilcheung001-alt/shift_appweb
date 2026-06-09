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
  final List<TextEditingController> compTimeCtrls = List.generate(rowCount, (_) => TextEditingController(text: '0.0'));
  final List<bool> useCompTime = List.generate(rowCount, (_) => false);
  final List<bool> _isSaving = List.generate(rowCount, (_) => false);

  final List<FocusNode> nameFocus = List.generate(rowCount, (_) => FocusNode());
  final List<FocusNode> reasonFocus = List.generate(rowCount, (_) => FocusNode());
  final List<FocusNode> daysFocus = List.generate(rowCount, (_) => FocusNode());

  final List<String> leaveTypes = ['AL', 'CL', 'SL', 'TR', '補鐘'];
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
    for (var c in compTimeCtrls) c.dispose();
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

  Map<String, dynamic> calculateDeduction({
    required String shift,
    required double requestedDays,
    required double compHoursUsed,
    required String leaveType,
  }) {
    final workHoursPerDay = getWorkHoursForShift(shift);
    final totalHoursNeeded = workHoursPerDay * requestedDays;

    // 補鐘：只扣補鐘
    if (leaveType == '補鐘') {
      return {'compUsed': compHoursUsed, 'alDays': 0.0, 'clDays': 0.0, 'slDays': 0.0};
    }

    // TR：唔扣任何嘢
    if (leaveType == 'TR') {
      return {'compUsed': 0.0, 'alDays': 0.0, 'clDays': 0.0, 'slDays': 0.0};
    }

    // 有剔補鐘：用小時計算
    if (compHoursUsed > 0) {
      final compUsed = compHoursUsed.clamp(0, totalHoursNeeded);
      final remainingHours = totalHoursNeeded - compUsed;

      if (remainingHours <= 0) {
        return {'compUsed': compUsed, 'alDays': 0.0, 'clDays': 0.0, 'slDays': 0.0};
      }

      if (leaveType == 'AL') {
        final alDays = remainingHours / 8.0;
        return {'compUsed': compUsed, 'alDays': alDays, 'clDays': 0.0, 'slDays': 0.0};
      }

      if (leaveType == 'CL') {
        // CL 有剔補鐘：先扣補鐘，再扣 CL 日數
        final clDays = remainingHours / 8.0;
        return {'compUsed': compUsed, 'alDays': 0.0, 'clDays': clDays, 'slDays': 0.0};
      }

      if (leaveType == 'SL') {
        final slDays = remainingHours / 8.0;
        return {'compUsed': compUsed, 'alDays': 0.0, 'clDays': 0.0, 'slDays': slDays};
      }
    }

    // 冇剔補鐘：用日數計算
    if (leaveType == 'AL') {
      double alDays = requestedDays;
      if (shift == 'LM' || shift == 'LN') {
        alDays = requestedDays * 1.5;
      }
      return {'compUsed': 0.0, 'alDays': alDays, 'clDays': 0.0, 'slDays': 0.0};
    }

    if (leaveType == 'CL') {
      double clDays = requestedDays;
      double alDays = 0.0;
      // 長班（LM/LN）：1日CL + 0.5日AL
      if ((shift == 'LM' || shift == 'LN') && requestedDays > 0) {
        alDays = requestedDays * 0.5;
      }
      return {'compUsed': 0.0, 'alDays': alDays, 'clDays': clDays, 'slDays': 0.0};
    }

    if (leaveType == 'SL') {
      return {'compUsed': 0.0, 'alDays': 0.0, 'clDays': 0.0, 'slDays': requestedDays};
    }

    return {'compUsed': 0.0, 'alDays': 0.0, 'clDays': 0.0, 'slDays': 0.0};
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
      final name = nameCtrls[row].text.trim();
      final reason = reasonCtrls[row].text.trim();
      final days = int.tryParse(daysCtrls[row].text.trim()) ?? 0;
      final compHoursInput = compTimeCtrls[row].text.trim();
      final compHours = compHoursInput.isEmpty ? 0.0 : double.tryParse(compHoursInput) ?? 0.0;
      final useComp = useCompTime[row];
      final type = typeSelected[row];

      if (name.isEmpty) {
        _showError('請填寫姓名');
        setState(() => _isSaving[row] = false);
        return;
      }
      if (days <= 0) {
        _showError('請填寫日數');
        setState(() => _isSaving[row] = false);
        return;
      }
      if (reason.isEmpty) {
        _showError('請填寫原因');
        setState(() => _isSaving[row] = false);
        return;
      }
      if (useComp && compHours <= 0) {
        _showError('請輸入補鐘時數');
        setState(() => _isSaving[row] = false);
        return;
      }

      final Map<String, Map<String, dynamic>> planByDate = {};
      final List<Map<String, dynamic>> deductionItems = [];

      int used = 0, offset = 0;
      while (used < days) {
        final target = widget.day.add(Duration(days: offset++));
        final shift = shiftForDate(target);
        // AL 休息日跳過，其他假可以請
        if (type == 'AL' && shift.isEmpty) continue;

        final dk = dateKey(target);
        if (!planByDate.containsKey(dk)) {
          planByDate[dk] = {
            'names': <String>[],
            'nicknames': <String>[],
            'reasons': <String>[],
            'compHours': <double>[],
            'shifts': <String>[],
            'leaveTypes': <String>[],
          };
        }

        planByDate[dk]!['names']!.add(name);
        planByDate[dk]!['nicknames']!.add(name == widget.myName ? widget.myNickname : '');
        planByDate[dk]!['reasons']!.add(reason);
        // 補鐘：每日扣相同時數
        planByDate[dk]!['compHours']!.add(useComp ? compHours : 0.0);
        planByDate[dk]!['shifts']!.add(shift);
        planByDate[dk]!['leaveTypes']!.add(type);

        deductionItems.add({'shift': shift, 'leaveType': type, 'compHours': useComp ? compHours : 0.0});
        used++;
      }

      if (planByDate.isEmpty) {
        _showError('無效請假（可能係休息日）');
        setState(() => _isSaving[row] = false);
        return;
      }

      double totalCompUsed = 0, totalALDays = 0, totalCLDays = 0, totalSLDays = 0;
      for (final item in deductionItems) {
        final calc = calculateDeduction(
          shift: item['shift'],
          requestedDays: 1,
          compHoursUsed: item['compHours'],
          leaveType: item['leaveType'],
        );
        totalCompUsed += calc['compUsed'];
        totalALDays += calc['alDays'];
        totalCLDays += calc['clDays'];
        totalSLDays += calc['slDays'];
      }

      // 詳細確認對話框
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
                if (days > 1) Text('📆 共 $days 日'),
                const Divider(),
                if (useComp) ...[
                  Text('💰 補鐘餘額: ${_compBalance.toStringAsFixed(1)} 小時'),
                  Text('🔻 使用補鐘: ${totalCompUsed.toStringAsFixed(1)} 小時'),
                  Text('📊 補鐘剩餘: ${(_compBalance - totalCompUsed).toStringAsFixed(1)} 小時'),
                  const Divider(),
                ],
                if (totalALDays > 0)
                  Text('🏖️ 將扣 AL: ${totalALDays.toStringAsFixed(1)} 日',
                      style: const TextStyle(color: Colors.blue)),
                if (totalCLDays > 0)
                  Text('🏢 將扣 CL: ${totalCLDays.toStringAsFixed(1)} 日',
                      style: const TextStyle(color: Colors.orange)),
                if (totalSLDays > 0)
                  Text('🤒 將扣 SL: ${totalSLDays.toStringAsFixed(1)} 日',
                      style: const TextStyle(color: Colors.green)),
                const SizedBox(height: 8),
                Text('💡 長班 (LM/LN): AL=1.5日, CL=1日+0.5日AL',
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
          'alDays': totalALDays,
          'clDays': totalCLDays,
          'slDays': totalSLDays,
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
                                onPressed: () {
                                  setState(() {
                                    nameCtrls[i].clear();
                                    reasonCtrls[i].clear();
                                    daysCtrls[i].text = '1';
                                    compTimeCtrls[i].text = '0.0';
                                    useCompTime[i] = false;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              SizedBox(
                                width: 100,
                                child: DropdownButtonFormField<String>(
                                  value: typeSelected[i],
                                  items: leaveTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(() {
                                      typeSelected[i] = v;
                                      if (v == 'AL') reasonCtrls[i].text = 'AL';
                                      if (v == 'CL') reasonCtrls[i].text = 'CL';
                                      if (v == 'SL') reasonCtrls[i].text = 'SL';
                                      if (v == 'TR') reasonCtrls[i].text = 'Training';
                                      if (v == '補鐘') reasonCtrls[i].text = '補鐘';
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
                                  decoration: const InputDecoration(labelText: '原因', isDense: true, border: OutlineInputBorder()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 60,
                                child: TextField(
                                  controller: daysCtrls[i],
                                  focusNode: daysFocus[i],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(labelText: '日數', isDense: true, border: OutlineInputBorder()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: useCompTime[i],
                                onChanged: (value) {
                                  setState(() {
                                    useCompTime[i] = value ?? false;
                                    if (!useCompTime[i]) compTimeCtrls[i].text = '0.0';
                                  });
                                },
                              ),
                              const Text('用補鐘', style: TextStyle(fontSize: 12)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (useCompTime[i])
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          '當前補鐘餘額: ${_compBalance.toStringAsFixed(1)} 小時',
                                          style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    TextField(
                                      controller: compTimeCtrls[i],
                                      keyboardType: TextInputType.number,
                                      enabled: useCompTime[i],
                                      decoration: InputDecoration(
                                        labelText: '補鐘時數',
                                        hintText: '最多 ${_compBalance.toStringAsFixed(1)}',
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