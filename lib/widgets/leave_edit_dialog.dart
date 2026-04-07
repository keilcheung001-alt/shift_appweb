import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  final Set<String> publicHolidays; // yyyy-MM-dd
  final List<String> cycle; // 28 日循環，例如 ['','M','M',...]
  final DateTime cycleStart;
  final VoidCallback? onCancelMyPending; // 可選：由 FullCalendar 傳入，真實取消 pending leave

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

  final List<FocusNode> nameFocus =
  List.generate(rowCount, (_) => FocusNode());
  final List<FocusNode> reasonFocus =
  List.generate(rowCount, (_) => FocusNode());
  final List<FocusNode> daysFocus =
  List.generate(rowCount, (_) => FocusNode());

  final List<String> leaveTypes = ['AL', 'CL', 'SL', 'TR'];
  late List<String> typeSelected;

  @override
  void initState() {
    super.initState();
    typeSelected = List<String>.filled(rowCount, leaveTypes.first);

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

  @override
  void dispose() {
    for (final c in nameCtrls) {
      c.dispose();
    }
    for (final c in reasonCtrls) {
      c.dispose();
    }
    for (final c in daysCtrls) {
      c.dispose();
    }
    for (final f in nameFocus) {
      f.dispose();
    }
    for (final f in reasonFocus) {
      f.dispose();
    }
    for (final f in daysFocus) {
      f.dispose();
    }
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
    }
  }

  void nextField(int row, int col) {
    int r = row;
    int c = col + 1;
    if (c > 2) {
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
    // 先做基本驗證：有名就要有原因
    bool hasAnyRow = false;
    bool missingReason = false;

    for (int i = 0; i < rowCount; i++) {
      final name = nameCtrls[i].text.trim();
      final reason = reasonCtrls[i].text.trim();
      final days = int.tryParse(daysCtrls[i].text.trim()) ?? 0;

      if (name.isEmpty || days <= 0) continue;
      hasAnyRow = true;
      if (reason.isEmpty) {
        missingReason = true;
      }
    }

    if (!hasAnyRow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少輸入一行姓名')),
      );
      return;
    }

    if (missingReason) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('有填姓名嘅行必須填寫原因')),
      );
      return;
    }

    final Map<String, List<String>> namesByDate = {};
    final Map<String, List<String>> reasonsByDate = {};

    for (int i = 0; i < rowCount; i++) {
      final name = nameCtrls[i].text.trim();
      var reason = reasonCtrls[i].text.trim();
      final days = int.tryParse(daysCtrls[i].text.trim()) ?? 0;
      if (name.isEmpty || days <= 0) continue;

      final type = typeSelected[i];  // 取得當前行的請假類型
      // 將類型同原因合併存入，方便 summary 顯示，例如：AL-旅行
      if (reason.isEmpty) {
        reason = type;
      } else {
        reason = '$type-$reason';
      }

      int used = 0;
      int offset = 0;

      while (used < days) {
        final target = widget.day.add(Duration(days: offset));
        offset++;

        final shift = shiftForDate(target);
        final bool isRestDay = shift.isEmpty;  // 判斷是否休息日

        // 🚨 新邏輯：只有年假 (AL) 先要避開休息日，其他假就算休息日都可以請
        if (type == 'AL' && isRestDay) {
          // 跳過休息日，但唔扣日數（即係繼續 loop）
          continue;
        }

        // 其他情況（包括 AL 但非休息日，以及其他假）都正常計一日
        final dk = dateKey(target);
        namesByDate.putIfAbsent(dk, () => <String>[]);
        reasonsByDate.putIfAbsent(dk, () => <String>[]);

        namesByDate[dk]!.add(name);
        reasonsByDate[dk]!.add(reason);

        used++;
      }
    }

    if (namesByDate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('計算結果為空，可能全部都係休息日且係年假')),
      );
      return;
    }

    final Map<String, Map<String, dynamic>> planByDate = {};
    namesByDate.forEach((dk, names) {
      planByDate[dk] = {
        'names': names,
        'reasons': reasonsByDate[dk] ?? List<String>.filled(names.length, ''),
      };
    });

    if (!mounted) return;
    Navigator.of(context).pop(
      LeaveEditDialogResult(isCancelled: false, planByDate: planByDate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleDate = DateFormat('yyyy/M/d').format(widget.day);
    final titleText = '$titleDate - ${widget.shift}';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 頂部標題
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  const Icon(Icons.event, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titleText,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // 內容
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
                          // 第一行：人頭 + 姓名 + 垃圾桶
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.blue,
                                child: IconButton(
                                  icon: const Icon(Icons.person,
                                      color: Colors.white),
                                  padding: EdgeInsets.zero,
                                  onPressed: (widget.myName.isEmpty &&
                                      widget.myNickname.isEmpty)
                                      ? null
                                      : () {
                                    final toFill = widget.myName.isNotEmpty
                                        ? widget.myName
                                        : widget.myNickname;
                                    setState(() {
                                      nameCtrls[i].text = toFill;
                                      nameCtrls[i].selection =
                                          TextSelection.fromPosition(
                                            TextPosition(
                                                offset: toFill.length),
                                          );
                                    });
                                    // 填好名之後直接跳去「類型」再去「原因」
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
                                icon: const Icon(Icons.delete,
                                    color: Colors.red),
                                onPressed: () async {
                                  // 如果 FullCalendar 有傳入 onCancelMyPending，
                                  // 並且呢行係自己個名，可以真正取消 pending leave
                                  if (widget.onCancelMyPending != null &&
                                      nameCtrls[i].text.trim() ==
                                          widget.myName) {
                                    Navigator.of(context).pop(
                                      LeaveEditDialogResult(
                                        isCancelled: true,
                                        planByDate: const {},
                                      ),
                                    );
                                    widget.onCancelMyPending!.call();
                                    return;
                                  }

                                  // 否則只係清空表格
                                  setState(() {
                                    nameCtrls[i].clear();
                                    reasonCtrls[i].clear();
                                    daysCtrls[i].text = '1';
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 第二行：類型 + 原因 + 日數
                          Row(
                            children: [
                              // 類型
                              SizedBox(
                                width: 90,
                                child: DropdownButtonFormField<String>(
                                  value: typeSelected[i],
                                  items: leaveTypes
                                      .map(
                                        (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t),
                                    ),
                                  )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(() {
                                      typeSelected[i] = v;
                                      // ✅ 重點：根據類型自動填入原因
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
                                        case '補鐘':
                                          reasonCtrls[i].text = '補鐘';
                                          break;
                                        case 'TR':
                                          reasonCtrls[i].text = 'Training';
                                          break;
                                        default:
                                          reasonCtrls[i].text = '';
                                      }
                                      // 自動將焦點移到原因欄位
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
                              // 原因
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
                              // 日數
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
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),

            const Divider(height: 1),

            // 底部按鈕
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text(
                        '取消',
                        style: TextStyle(color: Colors.red),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop(
                          LeaveEditDialogResult(
                            isCancelled: true,
                            planByDate: const {},
                          ),
                        );
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