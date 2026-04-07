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
      final data = doc.data();
      final names = List<String>.from(data['names'] ?? []);
      final reasons = List<String>.from(data['reasons'] ?? []);
      final staffIds = List<String>.from(data['staffIds'] ?? []);
      final dateTimestamp = data['date'] as Timestamp?;
      final date = dateTimestamp?.toDate();

      final myIndex = staffIds.indexOf(staffId);
      if (myIndex >= 0 && myIndex < names.length && date != null) {
        leaves.add({
          'id': doc.id,
          'date': date,
          'leaveType': reasons[myIndex].split('-').first,
          'reason': reasons[myIndex],
          'days': data['days'] ?? 1,        // ← 加返逗號同預設值
          'status': data['status'] ?? 'pending',
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

          // ✅ 用 withValues() 取代 withOpacity() 消除警告
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
              title: Text('${item['leaveType']} - ${item['days']}日'),
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