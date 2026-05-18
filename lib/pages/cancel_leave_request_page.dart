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
  List<ApprovedLeaveItem> _approvedItems = [];

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    final team = await AuthUtil.getHomeGroup();
    final name = await AuthUtil.getUserName();
    final nickname = await AuthUtil.getUserNickname();
    setState(() {
      _myTeam = team.isEmpty ? 'A' : team;
      _myName = name;
      _myNickname = nickname;
    });
    await _loadApprovedLeaves();
  }

  Future<void> _loadApprovedLeaves() async {
    setState(() => _loading = true);
    final staffId = await AuthUtil.getStaffId();

    final collection = FIRESTORE_LEAVE_COLLECTIONS[_myTeam] ?? 'a_team_leave';
    final snapshot = await FirebaseFirestore.instance
        .collection(collection)
        .where('status', isEqualTo: 'approved')
        .get();

    final List<ApprovedLeaveItem> items = [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final dateStr = doc.id;

      DateTime? docDate;
      try {
        docDate = DateTime.parse(dateStr);
      } catch (e) {
        continue;
      }

      // 🎯 限制只撈出今天或未來的假期
      if (docDate.isAfter(today) || docDate.isAtSameMomentAs(today)) {
        final attendees = data['attendees'] as Map<String, dynamic>? ?? {};

        // 1️⃣ 條件一：檢查外層 Key 有沒有你的 Staff ID 號碼
        bool isMyLeaveById = attendees.containsKey(staffId);

        // 2️⃣ 條件二：檢查外層 Key 有沒有你的名字或暱稱
        bool isMyLeaveByName = attendees.containsKey(_myName) ||
                               (_myNickname.isNotEmpty && attendees.containsKey(_myNickname));

        // 3️⃣ 條件三：如果外層 Key 對不到，深入進去檢查每個人的內層 'name' 欄位
        if (!isMyLeaveByName) {
          attendees.forEach((key, value) {
            if (value is Map && value.containsKey('name')) {
              final currentName = value['name']?.toString() ?? '';
              if (currentName == _myName || currentName == _myNickname) {
                isMyLeaveByName = true;
              }
            }
          });
        }

        // 🎯 師兄你看！【號碼中】或者【名中】，只要二選一中一個就立刻放行！
        if (isMyLeaveById || isMyLeaveByName) {
          String leaveReason = '';

          // 聰明撈出請假原因（邊個中就撈邊個嘅 reason）
          if (isMyLeaveById && attendees[staffId] is Map) {
            leaveReason = attendees[staffId]['reason'] ?? '';
          } else if (attendees[_myName] is Map) {
            leaveReason = attendees[_myName]['reason'] ?? '';
          } else if (_myNickname.isNotEmpty && attendees[_myNickname] is Map) {
            leaveReason = attendees[_myNickname]['reason'] ?? '';
          } else {
            attendees.forEach((key, value) {
              if (value is Map && (value['name'] == _myName || value['name'] == _myNickname)) {
                leaveReason = value['reason'] ?? '';
              }
            });
          }

          items.add(ApprovedLeaveItem(
            docId: doc.id,
            dateKey: dateStr,
            date: docDate,
            team: _myTeam,
            name: _myName,
            reason: leaveReason,
            index: items.length,
          ));
        }
      }
    }

    setState(() {
      _approvedItems = items;
      _loading = false;
    });
  }

  Future<void> _cancelItem(ApprovedLeaveItem item) async {
    final staffId = await AuthUtil.getStaffId();
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
        'staffId': staffId,
        'name': item.name,
        'reason': item.reason,
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