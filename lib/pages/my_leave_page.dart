// lib/pages/my_leave_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../constants/constants.dart';
import '../utils/auth_util.dart';

class MyLeavePage extends StatefulWidget {
  const MyLeavePage({super.key});

  @override
  State<MyLeavePage> createState() => _MyLeavePageState();
}

class _MyLeavePageState extends State<MyLeavePage> {
  List<Map<String, dynamic>> _leaves = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMyLeaves();
  }

  // ✅ 核心輔助方法：根據當前使用者隊伍的 config_cycle 獲取動態班次
  Future<String> _getDynamicShiftForDate(String team, DateTime date) async {
    try {
      final collection = FIRESTORE_LEAVE_COLLECTIONS[team] ?? 'a_team_leave';
      final configDoc = await FirebaseFirestore.instance
          .collection(collection)
          .doc('config_cycle')
          .get();

      List<String> cycle = ['M', 'M', 'A', 'A', 'N', 'N', '', ''];
      DateTime cycleStart = DateTime(2026, 1, 1);

      if (configDoc.exists && configDoc.data() != null) {
        final data = configDoc.data()!;
        if (data['cycle'] != null) {
          cycle = List<String>.from(data['cycle']);
        }
        if (data['cycleStart'] != null) {
          if (data['cycleStart'] is Timestamp) {
            cycleStart = (data['cycleStart'] as Timestamp).toDate();
          } else if (data['cycleStart'] is String) {
            cycleStart = DateTime.parse(data['cycleStart']);
          }
        }
      }

      final d0 = DateTime(date.year, date.month, date.day);
      final base = DateTime(cycleStart.year, cycleStart.month, cycleStart.day);
      final diff = d0.difference(base).inDays;

      if (diff < 0 || cycle.isEmpty) return '未知班次';
      final idx = diff % cycle.length;
      final shiftCode = cycle[idx].trim().toUpperCase();

      if (shiftCode.isEmpty) return '休息日';
      return '$shiftCode 更';
    } catch (e) {
      return '未知班次';
    }
  }

  Future<void> _loadMyLeaves() async {
    final staffId = await AuthUtil.getStaffId();
    final team = await AuthUtil.getHomeGroup();
    if (staffId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    final collection = FIRESTORE_LEAVE_COLLECTIONS[team] ?? 'a_team_leave';
    final snapshot = await FirebaseFirestore.instance
        .collection(collection)
        .where('staffIds', arrayContains: staffId)
        .orderBy('date', descending: true)
        .get();

    final List<Map<String, dynamic>> leaves = [];

    for (final doc in snapshot.docs) {
      if (doc.id == 'config_cycle' || doc.id == 'config_sheets') continue; // 跳過設定檔

      final data = doc.data();
      final names = List<String>.from(data['names'] ?? []);
      final reasons = List<String>.from(data['reasons'] ?? []);
      final staffIds = List<String>.from(data['staffIds'] ?? []);
      final dateTimestamp = data['date'] as Timestamp?;
      final date = dateTimestamp?.toDate();

      final myIndex = staffIds.indexOf(staffId);
      if (myIndex >= 0 && myIndex < names.length && date != null) {
        // 動態讀取當前隊伍對應日期的班次
        final shift = await _getDynamicShiftForDate(team, date);

        leaves.add({
          'id': doc.id,
          'date': date,
          'leaveType': reasons[myIndex].split('-').first,
          'reason': reasons[myIndex],
          'days': data['days'] ?? 1,
          'status': data['status'] ?? 'pending',
          'shift': shift,
        });
      }
    }

    setState(() {
      _leaves = leaves;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的請假'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _leaves.isEmpty
          ? const Center(child: Text('暫無請假記錄'))
          : ListView.builder(
        itemCount: _leaves.length,
        itemBuilder: (ctx, i) {
          final item = _leaves[i];
          final statusColor = item['status'] == 'approved'
              ? Colors.green
              : item['status'] == 'rejected'
              ? Colors.red
              : Colors.orange;

          final bgColor = statusColor.withValues(alpha: 0.2);

          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: bgColor,
                child: Icon(
                  item['status'] == 'approved'
                      ? Icons.check
                      : item['status'] == 'rejected'
                      ? Icons.close
                      : Icons.hourglass_empty,
                  color: statusColor,
                ),
              ),
              title: Row(
                children: [
                  Text('${item['leaveType']} - ${item['days']}日'),
                  const SizedBox(width: 12),
                  // ✅ UI 修正優化：將計算好嘅動態班次，用漂亮的藍色小外框標籤顯示在標題右邊！
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text(
                      item['shift'],
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                '${DateFormat('yyyy-MM-dd').format(item['date'])} ${item['reason'].isNotEmpty ? ' · ${item['reason']}' : ''}',
              ),
              trailing: Chip(
                label: Text(item['status']),
                backgroundColor: bgColor,
              ),
            ),
          );
        },
      ),
    );
  }
}