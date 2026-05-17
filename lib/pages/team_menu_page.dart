import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/shift_calculator.dart';
import '../constants/constants.dart';
import 'my_leave_page.dart';
import 'cancel_leave_request_page.dart';
import 'announcement_page.dart';
import 'whatsapp_config_page.dart';

// 🟢 修正一：由 Widget 改回 StatefulWidget，修復 createElement 錯誤
class TeamMenuPage extends StatefulWidget {
  final String? role;
  final String? staffId;
  final String? group;
  final bool? canFullEdit;
  final bool? isSuperAdmin; // 🟢 修正二：補回 main.dart 傳進來的參數

  const TeamMenuPage({
    super.key,
    this.role,
    this.staffId,
    this.group,
    this.canFullEdit,
    this.isSuperAdmin, // 🟢 補回構造函數參數
  });

  @override
  State<TeamMenuPage> createState() => _TeamMenuPageState();
}

class _TeamMenuPageState extends State<TeamMenuPage> {
  String _currentTeam = 'A';
  bool _isLoading = true;
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _loadUserTeam();
  }

  Future<void> _loadUserTeam() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentTeam = widget.group ?? prefs.getString(SPK_GROUP) ?? 'A';
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('$_currentTeam 隊 更表與管理'),
        backgroundColor: Colors.orange,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📅 廠房排班月曆 (手勢放大縮小)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 3,
              child: SizedBox(
                height: 400,
                child: GestureDetector(
                  onDoubleTap: () {
                    _transformationController.value = Matrix4.identity();
                  },
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.white,
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: 35,
                        itemBuilder: (context, index) {
                          final today = DateTime.now();
                          final date = DateTime(today.year, today.month, index - 2);

                          final shiftCode = ShiftCalculator.calculateShift(_currentTeam, date);
                          final isRest = ShiftCalculator.isRestDay(shiftCode);

                          return Container(
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isRest ? Colors.grey.shade100 : Colors.orange.shade50,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${date.day}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                Text(shiftCode, style: TextStyle(fontSize: 10, color: isRest ? Colors.grey : Colors.orange.shade900)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('🛠️ 員工功能選單', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.assignment, color: Colors.orange),
                    title: const Text('我的請假記錄'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MyLeavePage()),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cancel, color: Colors.red),
                    title: const Text('取消請假申請'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const CancelLeaveRequestPage()),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.campaign, color: Colors.blue),
                    title: const Text('廠房最新公告'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AnnouncementPage(
                            team: _currentTeam,
                            canEdit: widget.role == 'admin' || (widget.canFullEdit ?? false) || (widget.isSuperAdmin ?? false),
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.chat, color: Colors.green),
                    title: const Text('通知群組設定 (WhatsApp)'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const WhatsappConfigPage()),
                      );
                    },
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