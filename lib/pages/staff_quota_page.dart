// lib/pages/staff_quota_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/auth_util.dart';
import '../constants/constants.dart';

class StaffQuotaPage extends StatefulWidget {
  const StaffQuotaPage({super.key});

  @override
  State<StaffQuotaPage> createState() => _StaffQuotaPageState();
}

class _StaffQuotaPageState extends State<StaffQuotaPage> {
  bool _isAdmin = false;
  bool _loading = true;
  String _currentStaffId = '';
  String _currentTeam = '';

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final isSuperAdmin = await AuthUtil.getIsSuperAdmin();
    final isTeamLead = await AuthUtil.getIsTeamLead();
    _isAdmin = isSuperAdmin || isTeamLead;
    _currentStaffId = await AuthUtil.getStaffId();
    _currentTeam = (await AuthUtil.getHomeGroup()).toUpperCase();
    if (_currentTeam.isEmpty) _currentTeam = 'A';
    setState(() => _loading = false);
  }

  /// 獲取指定員工本年已批准的請假天數 (AL/CL/SL) 及補鐘時數 (compUsed)
  Future<Map<String, double>> _fetchUsedLeaves(String staffId, String team) async {
    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1);
    final yearStartStr = '${yearStart.year}-${yearStart.month.toString().padLeft(2, '0')}-${yearStart.day.toString().padLeft(2, '0')}';
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final collectionName = FIRESTORE_LEAVE_COLLECTIONS[team] ?? 'a_team_leave';
    final querySnapshot = await FirebaseFirestore.instance
        .collection(collectionName)
        .where('dateKey', isGreaterThanOrEqualTo: yearStartStr)
        .where('dateKey', isLessThanOrEqualTo: todayStr)
        .get();

    double usedAL = 0.0;
    double usedCL = 0.0;
    double usedSL = 0.0;
    double usedComp = 0.0;   // 小時

    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      final names = List<String>.from(data['names'] ?? []);
      final staffIds = List<String>.from(data['staffIds'] ?? []);
      final statuses = List<String>.from(data['statuses'] ?? []);
      final alHoursList = (data['alHours'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [];
      final clHoursList = (data['clHours'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [];
      final slHoursList = (data['slHours'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [];
      final compHoursList = (data['compHours'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [];

      int idx = -1;
      // 先嘗試用 staffId 匹配
      if (_currentStaffId.isNotEmpty) {
        idx = staffIds.indexOf(staffId);
      }
      // 若無則用 name 匹配 (兼容舊數據)
      if (idx == -1) {
        idx = names.indexOf(staffId);
      }
      if (idx == -1) continue;

      final status = idx < statuses.length ? statuses[idx] : 'pending';
      if (status != 'approved') continue;

      if (idx < alHoursList.length) usedAL += alHoursList[idx] / 8.0;
      if (idx < clHoursList.length) usedCL += clHoursList[idx] / 8.0;
      if (idx < slHoursList.length) usedSL += slHoursList[idx] / 8.0;
      if (idx < compHoursList.length) usedComp += compHoursList[idx];
    }

    return {
      'al': usedAL,
      'cl': usedCL,
      'sl': usedSL,
      'comp': usedComp,
    };
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

          // 對於員工視角，只顯示自己的資料 (直接過濾)
          Iterable<QueryDocumentSnapshot> displayList = staffList;
          if (!_isAdmin) {
            displayList = staffList.where((doc) => doc.id == _currentStaffId);
          }

          return ListView.builder(
            itemCount: displayList.length,
            itemBuilder: (context, index) {
              final doc = displayList.elementAt(index);
              final data = doc.data() as Map<String, dynamic>;
              final staffId = doc.id;
              final name = data['name'] ?? staffId;
              final team = data['team'] ?? 'A';
              final al = (data['al'] as num?)?.toDouble() ?? 0;
              final cl = (data['cl'] as num?)?.toDouble() ?? 0;
              final sl = (data['sl'] as num?)?.toDouble() ?? 0;
              final compTime = (data['compTime'] as num?)?.toDouble() ?? 0;

              final isSelf = (!_isAdmin && staffId == _currentStaffId);
              return FutureBuilder<Map<String, double>>(
                future: isSelf ? _fetchUsedLeaves(staffId, team) : Future.value(null),
                builder: (context, usedSnapshot) {
                  final usedData = usedSnapshot.data;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        ListTile(
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
                        if (isSelf && usedSnapshot.connectionState == ConnectionState.done && usedData != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _buildUsedChip('AL 本年已用', usedData['al']!, Colors.blue),
                                _buildUsedChip('CL 本年已用', usedData['cl']!, Colors.orange),
                                _buildUsedChip('SL 本年已用', usedData['sl']!, Colors.green),
                                _buildUsedChip('補鐘 本年已用', usedData['comp']!, Colors.purple, isHours: true),
                              ],
                            ),
                          ),
                        if (isSelf && usedSnapshot.connectionState == ConnectionState.waiting)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: SizedBox(height: 20, child: LinearProgressIndicator()),
                          ),
                      ],
                    ),
                  );
                },
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

  Widget _buildUsedChip(String label, double value, Color color, {bool isHours = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: ${value.toStringAsFixed(1)}${isHours ? ' 小時' : ' 日'}',
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