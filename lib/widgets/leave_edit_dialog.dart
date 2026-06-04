import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 引入網頁端事實判斷工具
import '../services/google_sheets_service.dart'; // 引入試算表服務

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
    // 1. 基本驗證：有名就要有原因
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
    final Map<String, List<String>> nicknamesByDate = {};
    final Map<String, List<String>> reasonsByDate = {};

    for (int i = 0; i < rowCount; i++) {
      final name = nameCtrls[i].text.trim();
      var reason = reasonCtrls[i].text.trim();
      final days = int.tryParse(daysCtrls[i].text.trim()) ?? 0;
      if (name.isEmpty || days <= 0) continue;

      final type = typeSelected[i];

      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請填寫原因，不可以留空')),
        );
        return;
      }

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
        namesByDate.putIfAbsent(dk, () => <String>[]);
        nicknamesByDate.putIfAbsent(dk, () => <String>[]);
        reasonsByDate.putIfAbsent(dk, () => <String>[]);

        namesByDate[dk]!.add(name);
        final nickname = (name == widget.myName) ? widget.myNickname : '';
        nicknamesByDate[dk]!.add(nickname);
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
        'nicknames': nicknamesByDate[dk] ?? [],
        'reasons': reasonsByDate[dk] ?? List<String>.filled(names.length, ''),
      };
    });

    // -------------------------------------------------------------------------
    // 【網頁端極速並行保底上傳通道】
    // -------------------------------------------------------------------------
    if (kIsWeb) {
      // 顯示加載圈圈
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        String detectedTeam = 'A'; // 預設值

        // 收集所有需要提交的請求 Future，準備進行非同步並行發送
        final List<Future<Map<String, dynamic>>> uploadFutures = [];

        for (var entry in planByDate.entries) {
          final dk = entry.key;
          final names = entry.value['names'] as List<String>;
          final nicknames = entry.value['nicknames'] as List<String>;
          final reasons = entry.value['reasons'] as List<String>;

          for (int idx = 0; idx < names.length; idx++) {
            // 將每個發送請求加入列表，暫不 await
            uploadFutures.add(
              GoogleSheetsService.submitLeaveWithForcedFallback(
                team: detectedTeam,
                userName: names[idx],
                nickname: nicknames[idx],
                employeeId: '',
                positionCode: '',
                dateKey: dk,
                reason: reasons[idx],
                days: 1.0,
                status: 'pending',
              ),
            );
          }
        }

        // 使用 Future.wait 同時發射所有請求，大幅減少多天請假造成的延遲！
        final List<Map<String, dynamic>> results = await Future.wait(uploadFutures);

        if (!mounted) return;
        Navigator.of(context).pop(); // 關閉進度條

        // 檢查是否有任何一筆失敗
        final bool anyFailure = results.any((res) => res['success'] != true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(anyFailure ? '部分數據提交可能未完全成功，請重新整理確認。' : '網頁端數據已極速保底同步！'),
            backgroundColor: anyFailure ? Colors.orange : Colors.green,
          ),
        );
      } catch (webErr) {
        if (!mounted) return;
        Navigator.of(context).pop(); // 關閉進度條
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('網頁連線異常: $webErr'), backgroundColor: Colors.red),
        );
      }
    }

    if (!mounted) return;
    // 返回結果給本地 UI 更新
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
                                      // ⭐ 已修正：正確格式化 TextSelection.fromPosition 語法
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
                                icon: const Icon(Icons.delete,
                                    color: Colors.red),
                                onPressed: () async {
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
                          Row(
                            children: [
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
                                        default:
                                          reasonCtrls[i].text = '';
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
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),

            const Divider(height: 1),

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