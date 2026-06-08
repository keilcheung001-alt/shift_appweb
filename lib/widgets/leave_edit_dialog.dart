// lib/widgets/leave_edit_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/google_sheets_service.dart';
import '../services/quota_service.dart';
import '../services/compensatory_time_service.dart';
import '../utils/auth_util.dart';
import '../constants/constants.dart';

class LeaveEditDialogResult {
  final bool isCancelled;
  final Map<String, Map<String, dynamic>> planByDate;

  LeaveEditDialogResult({
    required this.isCancelled,
    required this.planByDate,
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

  final List<TextEditingController> nameCtrls =
  List.generate(rowCount, (_) => TextEditingController());
  final List<TextEditingController> reasonCtrls =
  List.generate(rowCount, (_) => TextEditingController());
  final List<TextEditingController> daysCtrls =
  List.generate(rowCount, (_) => TextEditingController(text: '1'));

  final List<TextEditingController> compTimeCtrls =
  List.generate(rowCount, (_) => TextEditingController(text: '0'));
  final List<bool> useCompTime = List.generate(rowCount, (_) => false);

  final List<FocusNode> nameFocus = List.generate(rowCount, (_) => FocusNode());
  final List<FocusNode> reasonFocus = List.generate(rowCount, (_) => FocusNode());
  final List<FocusNode> daysFocus = List.generate(rowCount, (_) => FocusNode());
  final List<FocusNode> compFocus = List.generate(rowCount, (_) => FocusNode());

  // 🆕 加入「補鐘」選項
  final List<String> leaveTypes = ['AL', 'CL', 'SL', 'TR', '補鐘'];
  late List<String> typeSelected;

  double _compBalance = 0.0;
  String _staffId = '';
  Map<String, dynamic>? _quota;

  @override
  void initState() {
    super.initState();
    typeSelected = List<String>.filled(rowCount, leaveTypes.first);
    _loadData();

    for (int i = 0; i < rowCount; i++) {
      if (i < widget.initNames.length) {
        nameCtrls[i].text = widget.initNames[i];
      }
      if (i < widget.initReasons.length) {
        reasonCtrls[i].text = widget.initReasons[i];
      }
      if (i < widget.initDays.length && widget.initDays[i] > 0) {
        daysCtrls[i].text = widget.initDays[i].toString();
      }
    }
  }

  Future<void> _loadData() async {
    _staffId = await AuthUtil.getStaffId();
    _compBalance = await CompensatoryTimeService.getBalance(_staffId);
    _quota = await QuotaService.getCurrentQuota(_staffId);
    setState(() {});
  }

  @override
  void dispose() {
    for (final c in nameCtrls) c.dispose();
    for (final c in reasonCtrls) c.dispose();
    for (final c in daysCtrls) c.dispose();
    for (final c in compTimeCtrls) c.dispose();
    for (final f in nameFocus) f.dispose();
    for (final f in reasonFocus) f.dispose();
    for (final f in daysFocus) f.dispose();
    for (final f in compFocus) f.dispose();
    super.dispose();
  }

  String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String shiftForDate(DateTime date) {
    final d0 = DateTime(date.year, date.month, date.day);
    final base = DateTime(widget.cycleStart.year, widget.cycleStart.month,
        widget.cycleStart.day);
    final diff = d0.difference(base).inDays;
    if (diff < 0) return '';
    if (widget.cycle.isEmpty) return '';
    final idx = diff % widget.cycle.length;
    return widget.cycle[idx];
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

  /// 🎯 核心扣減邏輯
  Map<String, dynamic> calculateDeduction({
    required String shift,
    required double requestedDays,
    required double compHoursUsed,
    required String leaveType,
  }) {
    final workHoursPerDay = getWorkHoursForShift(shift);
    final totalHoursNeeded = workHoursPerDay * requestedDays;

    final compUsed = compHoursUsed.clamp(0, totalHoursNeeded);
    final remainingHours = totalHoursNeeded - compUsed;

    const Set<String> longShifts = {'LM', 'LN'};
    final isLongShift = longShifts.contains(shift);

    double alDays = 0.0;
    double clDays = 0.0;
    double slDays = 0.0;

    if (remainingHours <= 0) {
      return {
        'compUsed': compUsed,
        'alDays': 0.0,
        'clDays': 0.0,
        'slDays': 0.0,
      };
    }

    switch (leaveType) {
      case 'AL':
        if (isLongShift) {
          alDays = (remainingHours / 8.0) * 1.5;
        } else {
          alDays = remainingHours / 8.0;
        }
        break;

      case 'CL':
        if (isLongShift) {
          clDays = 1.0;
          final remainingAfterCL = remainingHours - 8.0;
          if (remainingAfterCL > 0) {
            alDays = remainingAfterCL / 8.0;
          }
        } else {
          clDays = 1.0;
        }
        break;

      case 'SL':
        slDays = remainingHours / 8.0;
        break;

      case '補鐘':
      // 揀「補鐘」類型時，只扣補鐘，唔扣 AL/CL/SL
        break;

      default:
        alDays = remainingHours / 8.0;
        break;
    }

    return {
      'compUsed': compUsed,
      'alDays': alDays,
      'clDays': clDays,
      'slDays': slDays,
    };
  }

  void focusRow(int row, int col) {
    if (!mounted) return;
    switch (col) {
      case 0:
        FocusScope.of(context).requestFocus(nameFocus[row]);
        break;
      case 1:
        FocusScope.of(context).requestFocus(reasonFocus[row]);
        break;
      case 2:
        FocusScope.of(context).requestFocus(daysFocus[row]);
        break;
      case 3:
        FocusScope.of(context).requestFocus(compFocus[row]);
        break;
    }
  }

  void nextField(int row, int col) {
    int r = row;
    int c = col + 1;
    if (c > 3) {
      r++;
      c = 0;
    }
    if (r >= rowCount) {
      FocusScope.of(context).unfocus();
      return;
    }
    focusRow(r, c);
  }

  Future<void> _onSave() async {
    bool hasAnyRow = false;
    for (int i = 0; i < rowCount; i++) {
      final name = nameCtrls[i].text.trim();
      final days = int.tryParse(daysCtrls[i].text.trim()) ?? 0;
      if (name.isNotEmpty && days > 0) {
        hasAnyRow = true;
        break;
      }
    }

    if (!hasAnyRow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少輸入一行姓名')),
      );
      return;
    }

    final Map<String, Map<String, dynamic>> planByDate = {};
    final List<Map<String, dynamic>> deductionItems = [];

    for (int i = 0; i < rowCount; i++) {
      final name = nameCtrls[i].text.trim();
      final reason = reasonCtrls[i].text.trim();
      final days = int.tryParse(daysCtrls[i].text.trim()) ?? 0;
      final compHours = double.tryParse(compTimeCtrls[i].text.trim()) ?? 0;
      final useComp = useCompTime[i];

      if (name.isEmpty || days <= 0) continue;

      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請填寫原因')),
        );
        return;
      }

      final type = typeSelected[i];

      int used = 0;
      int offset = 0;

      while (used < days) {
        final target = widget.day.add(Duration(days: offset));
        offset++;

        final shift = shiftForDate(target);
        final bool isRestDay = shift.isEmpty;

        if (type == 'AL' && isRestDay) {
          continue;
        }

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
        planByDate[dk]!['compHours']!.add(useComp ? compHours / days : 0);
        planByDate[dk]!['shifts']!.add(shift);
        planByDate[dk]!['leaveTypes']!.add(type);

        deductionItems.add({
          'shift': shift,
          'leaveType': type,
          'compHours': useComp ? compHours / days : 0,
        });

        used++;
      }
    }

    if (planByDate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無效嘅請假申請')),
      );
      return;
    }

    double totalCompUsed = 0;
    double totalALDays = 0;
    double totalCLDays = 0;
    double totalSLDays = 0;

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

    bool hasWarning = false;
    if (_quota != null) {
      final currentAL = (_quota!['al'] as num?)?.toDouble() ?? 0.0;
      final currentCL = (_quota!['cl'] as num?)?.toDouble() ?? 0.0;
      final currentSL = (_quota!['sl'] as num?)?.toDouble() ?? 0.0;

      if (totalALDays > currentAL) hasWarning = true;
      if (totalCLDays > currentCL) hasWarning = true;
      if (totalSLDays > currentSL) hasWarning = true;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('請假扣減確認'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('👤 員工: ${widget.myName}'),
              Text('📅 日期: ${DateFormat('yyyy-MM-dd').format(widget.day)}'),
              const Divider(),
              Text('💰 補鐘餘額: ${_compBalance.toStringAsFixed(1)} 小時'),
              Text('🔻 使用補鐘: ${totalCompUsed.toStringAsFixed(1)} 小時'),
              Text('📊 補鐘剩餘: ${(_compBalance - totalCompUsed).toStringAsFixed(1)} 小時'),
              const Divider(),
              if (totalALDays > 0)
                Text('🏖️ 將扣 AL: ${totalALDays.toStringAsFixed(1)} 日',
                    style: const TextStyle(color: Colors.blue)),
              if (totalCLDays > 0)
                Text('🏢 將扣 CL: ${totalCLDays.toStringAsFixed(1)} 日',
                    style: const TextStyle(color: Colors.orange)),
              if (totalSLDays > 0)
                Text('🤒 將扣 SL: ${totalSLDays.toStringAsFixed(1)} 日',
                    style: const TextStyle(color: Colors.green)),
              if (hasWarning) ...[
                const Divider(),
                const Text('⚠️ 警告：假期配額可能不足，仍會繼續處理',
                    style: TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 8),
              Text(
                '💡 長班 (LM/LN) AL = 1.5日，CL = 1日 + 剩餘轉AL',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              Text(
                '💡 病假 1日 = 8小時',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              Text(
                '💡 補鐘類型只扣補鐘，唔扣 AL/CL/SL',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
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

    if (confirm != true) return;

    // 扣減補鐘
    if (totalCompUsed > 0) {
      await CompensatoryTimeService.deductCompTime(_staffId, totalCompUsed);
    }

    // 扣減 AL/CL/SL
    if (totalALDays > 0) {
      await QuotaService.deductLeave(
        staffId: _staffId,
        leaveType: 'al',
        days: totalALDays,
        reason: '請假',
      );
    }
    if (totalCLDays > 0) {
      await QuotaService.deductLeave(
        staffId: _staffId,
        leaveType: 'cl',
        days: totalCLDays,
        reason: '請假',
      );
    }
    if (totalSLDays > 0) {
      await QuotaService.deductLeave(
        staffId: _staffId,
        leaveType: 'sl',
        days: totalSLDays,
        reason: '請假',
      );
    }

    if (widget.onCancelMyPending != null) {
      widget.onCancelMyPending!();
    }

    if (!mounted) return;

    String deductMsg = '';
    if (totalALDays > 0) deductMsg += 'AL ${totalALDays.toStringAsFixed(1)}日 ';
    if (totalCLDays > 0) deductMsg += 'CL ${totalCLDays.toStringAsFixed(1)}日 ';
    if (totalSLDays > 0) deductMsg += 'SL ${totalSLDays.toStringAsFixed(1)}日 ';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ 已提交請假，扣減: $deductMsg'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );

    if (mounted) {
      Navigator.of(context).pop(
        LeaveEditDialogResult(isCancelled: false, planByDate: planByDate),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleDate = DateFormat('yyyy/M/d').format(widget.day);
    final titleText = '$titleDate - ${widget.shift}';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  const Icon(Icons.event, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titleText,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '補鐘: ${_compBalance.toStringAsFixed(1)}h',
                      style: TextStyle(fontSize: 12, color: Colors.teal.shade800),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: List.generate(rowCount, (i) {
                    final isLast = i == rowCount - 1;
                    return Container(
                      margin: EdgeInsets.only(bottom: isLast ? 4 : 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          // 第一行：姓名 + 刪除
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.blue,
                                child: IconButton(
                                  icon: const Icon(Icons.person, color: Colors.white),
                                  padding: EdgeInsets.zero,
                                  onPressed: (widget.myName.isEmpty && widget.myNickname.isEmpty)
                                      ? null
                                      : () {
                                    final toFill = widget.myName.isNotEmpty
                                        ? widget.myName
                                        : widget.myNickname;
                                    setState(() {
                                      nameCtrls[i].text = toFill;
                                      nameCtrls[i].selection =
                                          TextSelection.fromPosition(
                                            TextPosition(offset: toFill.length),
                                          );
                                    });
                                    focusRow(i, 1);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: nameCtrls[i],
                                  focusNode: nameFocus[i],
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: '姓名',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => nextField(i, 0),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  if (widget.onCancelMyPending != null &&
                                      nameCtrls[i].text.trim() == widget.myName) {
                                    if (mounted) {
                                      Navigator.of(context).pop(
                                        LeaveEditDialogResult(
                                          isCancelled: true,
                                          planByDate: const {},
                                        ),
                                      );
                                    }
                                    if (widget.onCancelMyPending != null) {
                                      widget.onCancelMyPending!();
                                    }
                                    return;
                                  }
                                  setState(() {
                                    nameCtrls[i].clear();
                                    reasonCtrls[i].clear();
                                    daysCtrls[i].text = '1';
                                    compTimeCtrls[i].text = '0';
                                    useCompTime[i] = false;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 第二行：類型（🆕 加入「補鐘」選項）+ 原因 + 日數
                          Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: DropdownButtonFormField<String>(
                                  value: typeSelected[i],
                                  items: leaveTypes
                                      .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(() {
                                      typeSelected[i] = v;
                                      switch (v) {
                                        case 'AL':
                                          reasonCtrls[i].text = 'AL';
                                          break;
                                        case 'CL':
                                          reasonCtrls[i].text = 'CL';
                                          break;
                                        case 'SL':
                                          reasonCtrls[i].text = 'SL';
                                          break;
                                        case 'TR':
                                          reasonCtrls[i].text = 'Training';
                                          break;
                                        case '補鐘':
                                          reasonCtrls[i].text = '補鐘';
                                          break;
                                      }
                                      focusRow(i, 1);
                                    });
                                  },
                                  decoration: const InputDecoration(
                                    labelText: '類型',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: reasonCtrls[i],
                                  focusNode: reasonFocus[i],
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: '原因',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => nextField(i, 1),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 64,
                                child: TextField(
                                  controller: daysCtrls[i],
                                  focusNode: daysFocus[i],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(
                                    labelText: '日數',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => nextField(i, 2),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 第三行：補鐘選項（只負責計數，唔會改原因欄）
                          Row(
                            children: [
                              Checkbox(
                                value: useCompTime[i],
                                onChanged: (value) {
                                  setState(() {
                                    useCompTime[i] = value ?? false;
                                    if (!useCompTime[i]) {
                                      compTimeCtrls[i].text = '0';
                                    }
                                  });
                                },
                              ),
                              const Text('用補鐘', style: TextStyle(fontSize: 12)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: compTimeCtrls[i],
                                  focusNode: compFocus[i],
                                  keyboardType: TextInputType.number,
                                  enabled: useCompTime[i],
                                  decoration: InputDecoration(
                                    labelText: '補鐘時數',
                                    hintText: '最多 ${_compBalance.toStringAsFixed(1)}',
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                    suffixText: '小時',
                                  ),
                                  onSubmitted: (_) => nextField(i, 3),
                                ),
                              ),
                            ],
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
                      label: const Text('取消', style: TextStyle(color: Colors.red)),
                      onPressed: () {
                        if (mounted) {
                          Navigator.of(context).pop(
                            LeaveEditDialogResult(
                              isCancelled: true,
                              planByDate: const {},
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_box, color: Colors.white),
                      label: const Text('保存'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _onSave,
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