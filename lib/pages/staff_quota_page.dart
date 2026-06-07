// lib/pages/staff_quota_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/auth_util.dart';

class StaffQuotaPage extends StatefulWidget {
  const StaffQuotaPage({super.key});

  @override
  State<StaffQuotaPage> createState() => _StaffQuotaPageState();
}

class _StaffQuotaPageState extends State<StaffQuotaPage> {
  bool _isAdmin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final isSuperAdmin = await AuthUtil.getIsSuperAdmin();
    final isTeamLead = await AuthUtil.getIsTeamLead();
    _isAdmin = isSuperAdmin || isTeamLead;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? '調整員工假期' : '我的假期配額'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('user_quotas')
            .orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('錯誤: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final staffList = snapshot.data!.docs;
          if (staffList.isEmpty) {
            return const Center(child: Text('暫無員工資料'));
          }
          return ListView.builder(
            itemCount: staffList.length,
            itemBuilder: (context, index) {
              final doc = staffList[index];
              final data = doc.data() as Map<String, dynamic>;
              final staffId = doc.id;
              final name = data['name'] ?? staffId;
              final team = data['team'] ?? 'A';
              final al = (data['al'] as num?)?.toDouble() ?? 0;
              final cl = (data['cl'] as num?)?.toDouble() ?? 0;
              final sl = (data['sl'] as num?)?.toDouble() ?? 0;
              final compTime = (data['compTime'] as num?)?.toDouble() ?? 0;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.teal.shade100,
                    child: Text(
                      name.substring(0, 1).toUpperCase(),
                      style: TextStyle(color: Colors.teal.shade800, fontSize: 14),
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: Text('$staffId ｜ ${team}隊', style: const TextStyle(fontSize: 12)),
                  trailing: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      _buildChip('AL', al, Colors.blue),
                      _buildChip('CL', cl, Colors.orange),
                      _buildChip('SL', sl, Colors.green),
                      _buildChip('補鐘', compTime, Colors.purple, isHours: true),
                    ],
                  ),
                  onTap: _isAdmin ? () => _showEditDialog(staffId, data) : null,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildChip(String label, double value, Color color, {bool isHours = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: ${value.toStringAsFixed(0)}${isHours ? 'h' : ''}',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color),
      ),
    );
  }

  void _showEditDialog(String staffId, Map<String, dynamic> currentData) {
    final nameCtrl = TextEditingController(text: currentData['name'] ?? staffId);
    final teamCtrl = TextEditingController(text: currentData['team'] ?? 'A');
    final alCtrl = TextEditingController(text: (currentData['al'] ?? 0).toString());
    final clCtrl = TextEditingController(text: (currentData['cl'] ?? 0).toString());
    final slCtrl = TextEditingController(text: (currentData['sl'] ?? 0).toString());
    final compCtrl = TextEditingController(text: (currentData['compTime'] ?? 0).toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('編輯 $staffId'),
        content: SizedBox(
          width: 280,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名', isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: teamCtrl, decoration: const InputDecoration(labelText: '隊伍 (A/B/C/D)', isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: alCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '年假 AL (日)', isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: clCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '公司假 CL (日)', isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: slCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '病假 SL (日)', isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: compCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '補鐘 (小時)', isDense: true)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('user_quotas').doc(staffId).update({
                'name': nameCtrl.text.trim(),
                'team': teamCtrl.text.trim().toUpperCase(),
                'al': double.tryParse(alCtrl.text) ?? 0,
                'cl': double.tryParse(clCtrl.text) ?? 0,
                'sl': double.tryParse(slCtrl.text) ?? 0,
                'compTime': double.tryParse(compCtrl.text) ?? 0,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ 已更新'), duration: Duration(seconds: 1)),
              );
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}