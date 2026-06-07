// lib/pages/my_leave_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../constants/constants.dart';
import '../utils/auth_util.dart';
import '../services/quota_service.dart';

class MyLeavePage extends StatefulWidget {
  const MyLeavePage({super.key});

  @override
  State<MyLeavePage> createState() => _MyLeavePageState();
}

class _MyLeavePageState extends State<MyLeavePage> {
  List<Map<String, dynamic>> _leaves = [];
  bool _loading = true;

  // 假期配額
  Map<String, dynamic>? _quota;
  Stream<DocumentSnapshot>? _quotaStream;
  String _staffId = '';

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    _staffId = await AuthUtil.getStaffId();
    if (_staffId.isNotEmpty) {
      // 訂閱配額變化（實時更新）
      _quotaStream = QuotaService.streamQuota(_staffId);
      // 確保有配額記錄
      await QuotaService.getOrCreateQuota(_staffId);
    }
    await _loadMyLeaves();
    setState(() => _loading = false);
  }

  Future<void> _loadMyLeaves() async {
    final staffId = _staffId;
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

      final rawShift = data['shift'] as String? ?? '';
      final String shiftValue = rawShift.trim().isEmpty
          ? (data['shifts'] != null && (data['shifts'] as List).isNotEmpty ? data['shifts'][0].toString() : 'N/A')
          : rawShift;

      final dateTimestamp = data['date'] as Timestamp?;
      final date = dateTimestamp?.toDate();

      final myIndex = staffIds.indexOf(staffId);
      if (myIndex >= 0 && myIndex < names.length && date != null) {
        leaves.add({
          'id': doc.id,
          'date': date,
          'leaveType': reasons[myIndex].split('-').first,
          'reason': reasons[myIndex],
          'days': data['days'] ?? 1,
          'status': data['status'] ?? 'pending',
          'shift': shiftValue,
        });
      }
    }

    setState(() {
      _leaves = leaves;
    });
  }

  /// 顯示假期結算對話框
  void _showBalanceDetail() {
    if (_quota == null) {
      // 如果仲未 load 到，顯示 loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在載入假期資料...')),
      );
      return;
    }

    final al = (_quota!['al'] as num?)?.toDouble() ?? 0.0;
    final cl = (_quota!['cl'] as num?)?.toDouble() ?? 0.0;
    final sl = (_quota!['sl'] as num?)?.toDouble() ?? 0.0;
    final compTime = (_quota!['compTime'] as num?)?.toDouble() ?? 0.0;

    // 計算已用假期（從請假記錄）
    double usedAL = 0, usedCL = 0, usedSL = 0;
    for (final leave in _leaves) {
      if (leave['status'] == 'approved') {
        final type = leave['leaveType'];
        final days = (leave['days'] as num).toDouble();
        if (type == 'AL') usedAL += days;
        else if (type == 'CL') usedCL += days;
        else if (type == 'SL') usedSL += days;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.calculate, color: Colors.indigo),
            SizedBox(width: 8),
            Text('假期結算'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📅 即時餘額', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            _buildBalanceRow('🏖️ 年假 (AL)', al, Colors.blue),
            const SizedBox(height: 8),
            _buildBalanceRow('🏢 公司假 (CL)', cl, Colors.orange),
            const SizedBox(height: 8),
            _buildBalanceRow('🤒 病假 (SL)', sl, Colors.green),
            const SizedBox(height: 8),
            _buildBalanceRow('⏰ 補鐘', compTime, Colors.purple, isHours: true),
            const Divider(),
            const Text('📊 年度已用', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('已用年假: ${usedAL.toStringAsFixed(1)} 日'),
            Text('已用公司假: ${usedCL.toStringAsFixed(1)} 日'),
            Text('已用病假: ${usedSL.toStringAsFixed(1)} 日'),
            const Divider(),
            Text(
              '💡 病假每月 +4 日（上限 120 日）',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            Text(
              '💡 年假/公司假每年 1月1日 自動增加',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(String label, double value, Color color, {bool isHours = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '${value.toStringAsFixed(1)}${isHours ? ' 小時' : ' 日'}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的請假'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          // 顯示剩餘 AL（實時），點擊可開對話框
          if (_quotaStream != null)
            StreamBuilder<DocumentSnapshot>(
              stream: _quotaStream,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final al = (data['al'] as num?)?.toDouble() ?? 0.0;
                  // 儲存配額以便對話框使用
                  if (_quota == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        _quota = data;
                      });
                    });
                  } else {
                    _quota = data;
                  }
                  return GestureDetector(
                    onTap: _showBalanceDetail,
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.balance, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '剩餘 ${al.toStringAsFixed(1)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          IconButton(
            icon: const Icon(Icons.calculate),
            onPressed: _showBalanceDetail,
            tooltip: '假期結算',
          ),
        ],
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
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    '日期：${DateFormat('yyyy-MM-dd').format(item['date'])}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('班次：${item['shift']}'),
                  if (item['reason'].isNotEmpty) Text('原因：${item['reason']}'),
                ],
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
