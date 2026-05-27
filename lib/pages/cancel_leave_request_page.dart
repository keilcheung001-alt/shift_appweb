// lib/pages/cancel_leave_request_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/constants.dart';
import '../utils/auth_util.dart';

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
  String _myNickname = '';
  String _myStaffId = '';
  List<ApprovedLeaveItem> _approvedItems = [];

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    final team = await AuthUtil.getHomeGroup();
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(SPK_MY_NAME) ?? '';
    final nickname = prefs.getString(SPK_NICKNAME) ?? '';
    final staffId = await AuthUtil.getStaffId();
    setState(() {
      _myTeam = team.isEmpty ? 'A' : team;
      _myName = name;
      _myNickname = nickname;
      _myStaffId = staffId;
    });
    await _loadApprovedLeaves();
  }

  Future<void> _loadApprovedLeaves() async {
    setState(() => _loading = true);
    final collection = FIRESTORE_LEAVE_COLLECTIONS[_myTeam] ?? 'a_team_leave';

    // 查詢所有狀態為 approved 或 partial 的文件（因為 partial 也可能包含你的已批核假期）
    final snapshot = await FirebaseFirestore.instance
        .collection(collection)
        .where('status', whereIn: ['approved', 'partial'])
        .get();

    final List<ApprovedLeaveItem> items = [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final dateKey = data['dateKey'] ?? doc.id;

      DateTime? docDate;
      try {
        docDate = DateTime.parse(dateKey);
      } catch (e) {
        continue;
      }

      // 只顯示今天或未來的假期
      if (docDate.isBefore(today)) continue;

      // 讀取陣列資料
      final List<dynamic> names = data['names'] ?? [];
      final List<dynamic> reasons = data['reasons'] ?? [];
      final List<dynamic> statuses = data['statuses'] ?? [];
      final List<dynamic> nicknames = data['nicknames'] ?? [];
      final List<dynamic> staffIds = data['staffIds'] ?? [];

      // 搵出你的索引（根據 Staff ID 或姓名/暱稱）
      int myIndex = -1;

      // 優先使用 Staff ID 配對
      if (_myStaffId.isNotEmpty) {
        myIndex = staffIds.indexWhere((id) => id == _myStaffId);
      }

      // 如果 Staff ID 配對唔到，再用姓名或暱稱
      if (myIndex == -1) {
        myIndex = names.indexWhere((name) {
          if (name == _myName) return true;
          final nick = nicknames.isNotEmpty && nicknames.length > names.indexOf(name) ? nicknames[names.indexOf(name)] : '';
          return nick == _myName || nick == _myNickname;
        });
      }

      if (myIndex == -1) continue;

      // 檢查你的狀態是否為 approved（只有已批核的才能取消）
      final myStatus = myIndex < statuses.length ? statuses[myIndex] : 'pending';
      if (myStatus != 'approved') continue;

      // 讀取你的請假原因
      String myReason = myIndex < reasons.length ? reasons[myIndex] : '';

      items.add(ApprovedLeaveItem(
        docId: doc.id,
        dateKey: dateKey,
        date: docDate,
        team: _myTeam,
        name: _myName,
        reason: myReason,
        index: myIndex,
      ));
    }

    // 按日期排序（近到遠）
    items.sort((a, b) => a.date.compareTo(b.date));

    setState(() {
      _approvedItems = items;
      _loading = false;
    });
  }

  Future<void> _cancelItem(ApprovedLeaveItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認取消請假'),
        content: Text('您確定要申請取消 ${item.dateKey} 的請假嗎？\n提交後需等待管理員重新審批。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('暫時不要')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('確認提交', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);

    try {
      // 提交取消假期的申請
      await FirebaseFirestore.instance.collection('pending_cancel_leaves').add({
        'dateKey': item.dateKey,
        'team': item.team,
        'staffId': _myStaffId,
        'name': _myName,
        'nickname': _myNickname,
        'reason': item.reason,
        'originalStatus': 'approved',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 取消申請已提交，等待管理員審批'), backgroundColor: Colors.green),
        );
      }
      await _loadApprovedLeaves();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 提交失敗: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _loading = false);
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
          ? const Center(child: Text('暫無可取消的請假（未來日子）'))
          : ListView.builder(
              itemCount: _approvedItems.length,
              itemBuilder: (context, index) {
                final item = _approvedItems[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ListTile(
                    title: const Text('已批核假期', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      child: const Text('申請取消', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}