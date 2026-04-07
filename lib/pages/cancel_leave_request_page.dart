// lib/pages/cancel_leave_request_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/constants.dart';
import '../utils/auth_util.dart';
import '../services/google_sheets_service.dart';

class ApprovedLeaveItem {
  final String docId;
  final String dateKey;
  final DateTime date;
  final String team;
  final String name;
  final String reason;
  final int index;

  ApprovedLeaveItem({
    required this.docId,
    required this.dateKey,
    required this.date,
    required this.team,
    required this.name,
    required this.reason,
    required this.index,
  });
}

class CancelLeaveRequestPage extends StatefulWidget {
  const CancelLeaveRequestPage({super.key});

  @override
  State<CancelLeaveRequestPage> createState() => _CancelLeaveRequestPageState();
}

class _CancelLeaveRequestPageState extends State<CancelLeaveRequestPage> {
  bool _loading = true;
  String _myTeam = 'A';
  String _myName = '';
  List<ApprovedLeaveItem> _approvedItems = [];

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    _myTeam = await AuthUtil.getHomeGroup();
    _myName = await AuthUtil.getMyName();

    if (mounted) setState(() => _loading = false);
    _loadApprovedItems();
  }

  String _getCollectionName(String team) {
    return FIRESTORE_LEAVE_COLLECTIONS[team.toUpperCase()] ?? FIRESTORE_A_TEAM_LEAVE;
  }

  Future<void> _loadApprovedItems() async {
    try {
      final collectionName = _getCollectionName(_myTeam);
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final snapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .orderBy('date', descending: false)
          .get();

      final items = <ApprovedLeaveItem>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final dateKey = data['dateKey'] as String? ?? doc.id;
        final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.parse(dateKey);
        final names = List<String>.from(data['names'] ?? []);
        final reasons = List<String>.from(data['reasons'] ?? []);
        final statuses = List<String>.from(data['statuses'] ?? List.filled(names.length, 'pending'));

        for (int i = 0; i < names.length; i++) {
          if (names[i] == _myName && statuses[i] == 'approved') {
            items.add(ApprovedLeaveItem(
              docId: doc.id,
              dateKey: dateKey,
              date: date,
              team: _myTeam,
              name: names[i],
              reason: i < reasons.length ? reasons[i] : '',
              index: i,
            ));
          }
        }
      }

      if (mounted) setState(() => _approvedItems = items);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 載入失敗: $e')),
        );
      }
    }
  }

  Future<void> _cancelItem(ApprovedLeaveItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認取消請假？'),
        content: Text('日期: ${item.dateKey}\n原因: ${item.reason.isNotEmpty ? item.reason : '無'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('返回')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認取消', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final collectionName = _getCollectionName(item.team);
      final docRef = FirebaseFirestore.instance.collection(collectionName).doc(item.docId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;

        final data = snap.data() as Map<String, dynamic>;
        final names = List<String>.from(data['names'] ?? []);
        final reasons = List<String>.from(data['reasons'] ?? []);
        final statuses = List<String>.from(data['statuses'] ?? List.filled(names.length, 'pending'));

        if (item.index >= statuses.length) return;
        statuses[item.index] = 'cancelled';

        tx.update(docRef, {
          'statuses': statuses,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      // ✅ 上傳 cancelled 記錄到 Google Sheets
      try {
        final prefs = await SharedPreferences.getInstance();
        final nickname = prefs.getString(SPK_NICKNAME) ?? '';
        final employeeId = prefs.getString(SPK_STAFF_ID) ?? '';
        final positionCode = prefs.getString(SPK_JOB_TITLE) ?? '';

        await GoogleSheetsService.uploadLeaveRecord(
          team: item.team,
          userName: item.name,
          nickname: nickname,
          employeeId: employeeId,
          positionCode: positionCode,
          dateKey: item.dateKey,
          reason: item.reason,
          days: 1,
          status: 'cancelled',
        );
      } catch (e) {
        debugPrint('❌ 上傳 cancelled 到 Google Sheets 失敗: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已取消請假')),
        );
        _loadApprovedItems();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 取消失敗: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('取消請假'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: _approvedItems.isEmpty
          ? const Center(child: Text('暫無可取消的請假'))
          : ListView.builder(
        itemCount: _approvedItems.length,
        itemBuilder: (context, index) {
          final item = _approvedItems[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListTile(
              title: const Text('請假申請', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('📅 日期: ${item.dateKey}'),
                  if (item.reason.isNotEmpty) Text('📝 原因: ${item.reason}'),
                ],
              ),
              trailing: ElevatedButton(
                onPressed: () => _cancelItem(item),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                child: const Text('取消', style: TextStyle(color: Colors.white)),
              ),
            ),
          );
        },
      ),
    );
  }
}