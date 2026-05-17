import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/shift_calculator.dart';
import '../constants/constants.dart';
import 'my_leave_page.dart';
import 'announcement_page.dart';
import 'desktop_widgets_page.dart';

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
  String _todayShift = '常班';

  Color _getTeamButtonColor(String team) {
    switch (team) {
      case 'A': return const Color(0xFF3F51B5);
      case 'B': return const Color(0xFFFF8F00);
      case 'C': return const Color(0xFF4CAF50);
      case 'D': return const Color(0xFF9C27B0);
      default: return Colors.indigo;
    }
  }

  @override
  void initState() {
    super.initState();
    final safeGroup = (widget.group == null || widget.group!.isEmpty) ? 'A' : widget.group!;
    _currentTeam = safeGroup;
    try {
      _todayShift = ShiftCalculator.calculateShift(safeGroup, DateTime.now());
    } catch (_) {
      _todayShift = '常班';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRole = widget.role ?? '員工';
    final userGroup = (widget.group == null || widget.group!.isEmpty) ? 'A' : widget.group!;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        title: const Text('隊伍管理選單', style: TextStyle(fontSize: 20)),
        backgroundColor: const Color(0xFF4A55A2),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacementNamed(context, ROUTE_LOGIN),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF3F51B5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: Text(userGroup, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('cheungyiukei', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('工號: ${widget.staffId ?? "583472"} (暱稱: 基)', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      Text('權限: $userRole | 所屬組別: $userGroup 隊', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign, color: Colors.orange, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('announcements')
                        .where('targetTeam', isEqualTo: _currentTeam)
                        .orderBy('timestamp', descending: true)
                        .limit(1)
                        .snapshots(),
                    builder: (context, snapshot) {
                      String txt = '一則 testing';
                      if (snapshot.hasData && snapshot.data != null && snapshot.data!.docs.isNotEmpty) {
                        final d = snapshot.data!.docs.first.data() as Map<String, dynamic>?;
                        if (d != null) txt = d['content']?.toString() ?? '一則 testing';
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('一則', style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text(txt, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                        ],
                      );
                    },
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.orange, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('隊伍日曆 (快速切換)    [今日: $_todayShift班]', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['A', 'B', 'C', 'D'].map((t) {
                final isSelected = _currentTeam == t;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentTeam = t;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      height: 55,
                      decoration: BoxDecoration(
                        color: _getTeamButtonColor(t),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? Colors.black87 : Colors.transparent, width: isSelected ? 3 : 0),
                      ),
                      child: Center(child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                _buildMenuTile(
                  icon: Icons.history,
                  title: '我的請假記錄',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyLeavePage())),
                ),
                _buildMenuTile(
                  icon: Icons.cancel_presentation_outlined,
                  title: '取消請假申請',
                  onTap: () {},
                ),
                _buildMenuTile(
                  icon: Icons.notifications_none,
                  title: '隊伍公告管理',
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => AnnouncementPage(team: userGroup, canEdit: true)));
                  },
                ),
                _buildMenuTile(
                  icon: Icons.grid_view,
                  title: '桌面小工具與鬧鐘',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DesktopWidgetsPage())),
                ),
                _buildMenuTile(
                  icon: Icons.gavel,
                  title: '審批請假申請',
                  onTap: () => Navigator.pushNamed(context, ROUTE_APPROVAL),
                ),
                _buildMenuTile(
                  icon: Icons.calendar_month_outlined,
                  title: '假期與自訂節日管理',
                  onTap: () => Navigator.pushNamed(context, ROUTE_HOLIDAYS),
                ),
                _buildMenuTile(
                  icon: Icons.settings,
                  title: 'Google Sheets 配置',
                  onTap: () => Navigator.pushNamed(context, ROUTE_GOOGLE_SHEETS_CONFIG),
                ),
                _buildMenuTile(
                  icon: Icons.chat_bubble_outline,
                  title: 'WhatsApp 通知配置',
                  onTap: () => Navigator.pushNamed(context, ROUTE_WHATSAPP_CONFIG),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({required IconData icon, required String title, required VoidCallback onTap}) {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF3F51B5)),
        title: Text(title, style: const TextStyle(color: Colors.black87, fontSize: 16)),
        trailing: const Icon(Icons.chevron_right, color: Colors.black26),
        onTap: onTap,
      ),
    );
  }
}