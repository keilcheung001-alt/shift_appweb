import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/shift_calculator.dart';
import '../constants/constants.dart';
import 'my_leave_page.dart';
import 'announcement_page.dart';
import '../screens/login_page.dart';

class TeamMenuPage extends StatefulWidget {
  final String? role;
  final String? staffId;
  final String? group;
  final bool? canFullEdit;
  final bool? isSuperAdmin;

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

  // 🎨 100% 還原第一張相：ABCD 四個隊伍按鈕的原裝代表色
  Color _getTeamColor(String team) {
    switch (team) {
      case 'A': return const Color(0xff3f51b5); // 靛藍色
      case 'B': return const Color(0xffff9800); // 橙色
      case 'C': return const Color(0xff4caf50); // 綠色
      case 'D': return const Color(0xff9c27b0); // 紫色
      default: return Colors.orange;
    }
  }

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

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // 清除本地登入快取
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

    final bool showAdminSection = widget.role == 'admin' ||
                                  (widget.canFullEdit ?? false) ||
                                  (widget.isSuperAdmin ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('隊伍管理選單', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xff3f51b5), // AppBar 藍色
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
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
            // 👤 1. 用戶資訊藍色大卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xff3f51b5), Color(0xff2196f3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    child: Text(
                      _currentTeam,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.staffId == '583472' ? 'cheungyiukei' : (widget.staffId ?? '未知用戶'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '工號: ${widget.staffId ?? "583472"} ${widget.staffId == "583472" ? "(暱稱: 基)" : ""}',
                        style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 📢 2. 一則公告黃色卡片
            Card(
              color: const Color(0xfffff9e6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xffffe0b2), width: 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.campaign, color: Colors.orange),
                title: const Text('一則', style: TextStyle(fontSize: 12, color: Colors.grey)),
                subtitle: const Text('testing', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                trailing: const Icon(Icons.chevron_right, color: Colors.orange),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AnnouncementPage(
                        team: _currentTeam,
                        canEdit: showAdminSection,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // 📅 3. 隊伍日曆 (快速切換標題)
            const Text(
              '隊伍日曆 (快速切換)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),

            // 四個彩色正方形隊伍按鈕
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['A', 'B', 'C', 'D'].map((team) {
                final isSelected = _currentTeam == team;
                final teamColor = _getTeamColor(team);
                return SizedBox(
                  width: MediaQuery.of(context).size.width * 0.21,
                  height: MediaQuery.of(context).size.width * 0.21,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? teamColor : teamColor.withOpacity(0.15),
                      foregroundColor: isSelected ? Colors.white : teamColor,
                      elevation: isSelected ? 4 : 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      setState(() {
                        _currentTeam = team;
                      });
                    },
                    child: Text(
                      team,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 📅 4. 主頁面的內嵌小月曆
            Card(
              elevation: 1,
              color: Colors.white,
              child: SizedBox(
                height: 340,
                child: GestureDetector(
                  onDoubleTap: () {
                    _transformationController.value = Matrix4.identity();
                  },
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          childAspectRatio: 1.1,
                        ),
                        itemCount: 35,
                        itemBuilder: (context, index) {
                          final today = DateTime.now();
                          final date = DateTime(today.year, today.month, index - 2);

                          final shiftCode = ShiftCalculator.calculateShift(_currentTeam, date);
                          final isRest = ShiftCalculator.isRestDay(shiftCode);
                          final color = ShiftCalculator.getShiftColor(shiftCode);

                          return Container(
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isRest ? Colors.grey.shade50 : color.withOpacity(0.05),
                              border: Border.all(
                                color: isRest ? Colors.grey.shade200 : color.withOpacity(0.4),
                                width: 1.2,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${date.day}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)
                                ),
                                Text(
                                  shiftCode,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isRest ? Colors.grey : color,
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

            // 🛠️ 5. 功能選單（已遵照指示：精確刪除「取消請假申請」，其餘絕不亂動）
            const Text('功能選單', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade200)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.history, color: Colors.indigo),
                    title: const Text('我的請假記錄'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.pushNamed(context, ROUTE_MY_LEAVE),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notifications_none, color: Colors.indigo),
                    title: const Text('隊伍公告管理'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AnnouncementPage(
                            team: _currentTeam,
                            canEdit: showAdminSection,
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.grid_view, color: Colors.indigo),
                    title: const Text('桌面小工具與鬧鐘'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.pushNamed(context, ROUTE_DESKTOP_WIDGETS), // 🟢 點擊跳轉到獨立的第二張圖畫面
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 👑 6. 管理員功能區面（保持最原始路由與外觀）
            if (showAdminSection) ...[
              const Text('管理員功能', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.redAccent)),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade200)),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.rate_review, color: Colors.indigo),
                      title: const Text('審批請假申請'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => Navigator.pushNamed(context, ROUTE_APPROVAL),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.calendar_today, color: Colors.indigo),
                      title: const Text('假期與自訂節日管理'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => Navigator.pushNamed(context, ROUTE_HOLIDAYS),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.settings, color: Colors.indigo),
                      title: const Text('Google Sheets 配置'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => Navigator.pushNamed(context, ROUTE_GOOGLE_SHEETS_CONFIG),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.chat_bubble_outline, color: Colors.indigo),
                      title: const Text('WhatsApp 通知配置'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => Navigator.pushNamed(context, ROUTE_WHATSAPP_CONFIG),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}