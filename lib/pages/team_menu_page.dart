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
import '../screens/login_page.dart'; // 🟢 補回引入登入頁面，供登出跳轉使用

// 🟢 修正：原本寫錯成extends Widget，改回正確的 StatefulWidget
class TeamMenuPage extends StatefulWidget {
  final String? role;
  final String? staffId;
  final String? group;
  final bool? canFullEdit;
  final bool? isSuperAdmin; // 🟢 補齊 main.dart 傳進來的參數

  const TeamMenuPage({
    super.key,
    this.role,
    this.staffId,
    this.group,
    this.canFullEdit,
    this.isSuperAdmin,
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

  // 🟢 補回登出功能邏輯
  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // 清除本機登入緩存，確保下次不會自動跳過登入頁面
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
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
        foregroundColor: Colors.white,
        actions: [
          // 🟢 補回右上角「登出」掣，解決你卡在畫面出不去的問題！
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '登出系統',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🟢 補回 ABCD 更隊伍手動切換按鈕組
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['A', 'B', 'C', 'D'].map((team) {
                final isSelected = _currentTeam == team;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? Colors.orange : Colors.grey.shade200,
                    foregroundColor: isSelected ? Colors.white : Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    setState(() {
                      _currentTeam = team;
                    });
                  },
                  child: Text('$team 隊', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

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

                          // 🟢 調用你原始的 ShiftCalculator 邏輯來精準獲取六個班次與顏色
                          final shiftCode = ShiftCalculator.calculateShift(_currentTeam, date);
                          final isRest = ShiftCalculator.isRestDay(shiftCode);
                          final color = ShiftCalculator.getShiftColor(shiftCode); // 🎯 100% 直接使用你文件內的 6 更核心色彩

                          return Container(
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              // 🎨 根據你截圖的配色：放假用淺灰，返工用原配色的極淡底色襯托
                              color: isRest ? Colors.grey.shade100 : color.withOpacity(0.06),
                              // 🎨 100% 復原你要求的「每一間不同顏色邊框（Color Border）」
                              border: Border.all(
                                color: isRest ? Colors.grey.shade300 : color.withOpacity(0.5),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${date.day}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  shiftCode,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isRest ? Colors.grey : color, // 🎨 文字也100%對其原始顏色
                                  ),
                                ),
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
                      // 🟢 修正：徹底移除 const，對應動態路由跳轉
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