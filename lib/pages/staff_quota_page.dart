import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StaffQuotaPage extends StatefulWidget {
  const StaffQuotaPage({super.key});

  @override
  State<StaffQuotaPage> createState() => _StaffQuotaPageState();
}

class _StaffQuotaPageState extends State<StaffQuotaPage> {
  final Stream<QuerySnapshot> _staffStream =
  FirebaseFirestore.instance.collection('user_quotas').snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('員工假期列表 (強制讀取)')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _staffStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('錯誤: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('資料庫內沒有任何資料'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return ListTile(
                title: Text(data['name'] ?? '未命名'),
                subtitle: Text('ID: ${docs[index].id} | 團隊: ${data['team'] ?? '無'}'),
                trailing: const Icon(Icons.edit),
                onTap: () => _showEditDialog(docs[index].id, data), // 🔥 加返呢行
              );
            },
          );
        },
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
        title: Text('編輯 ID: $staffId'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名')),
              TextField(controller: teamCtrl, decoration: const InputDecoration(labelText: '隊伍 (A/B/C/D)')),
              TextField(controller: alCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '年假 AL')),
              TextField(controller: clCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '公司假 CL')),
              TextField(controller: slCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '病假 SL')),
              TextField(controller: compCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '補鐘 (小時)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final Map<String, dynamic> updateData = {
                'name': nameCtrl.text.trim(),
                'team': teamCtrl.text.trim().toUpperCase(),
                'al': double.tryParse(alCtrl.text) ?? 0.0,
                'cl': double.tryParse(clCtrl.text) ?? 0.0,
                'sl': double.tryParse(slCtrl.text) ?? 0.0,
                'compTime': double.tryParse(compCtrl.text) ?? 0.0,
                'updatedAt': FieldValue.serverTimestamp(),
              };

              try {
                // 使用 set(merge: true) 確保文件存在或自動建立
                await FirebaseFirestore.instance
                    .collection('user_quotas')
                    .doc(staffId)
                    .set(updateData, SetOptions(merge: true));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ 更新成功，資料庫已同步')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('❌ 更新失敗: $e')),
                );
              }
            },
            child: const Text('儲存修改'),
          ),
        ],
      ),
    );
  }
}