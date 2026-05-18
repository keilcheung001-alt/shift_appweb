import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/shift_calculator.dart';
import '../constants/constants.dart';
import 'my_leave_page.dart';
import 'announcement_page.dart';
import 'desktop_widgets_page.dart';
import 'full_calendar_a.dart';
import 'full_calendar_b.dart';
import 'full_calendar_c.dart';
import 'full_calendar_d.dart';

class TeamMenuPage extends StatefulWidget {
  const TeamMenuPage({super.key});

  @override
  State<TeamMenuPage> createState() => _TeamMenuPageState();
}

class _TeamMenuPageState extends State<TeamMenuPage> {
  String _currentTeam = 'A';
  String _todayShift = '常班';
  String _userName = '';
  String _userNickname = '';
  String _userStaffId = '';
  String _userRole = '員工';
  String _userGroup = 'A';
  bool _isLoading = true;
  bool _isSuperAdmin = false;   // SM
  bool _isSR = false;           // SR (可管理自己隊)

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final group = prefs.getString(SPK_GROUP) ?? 'A';
      final staffId = prefs.getString(SPK_STAFF_ID) ?? '';
      final name = prefs.getString(SPK_MY_NAME) ?? '';
      final nickname = prefs.getString(SPK_NICKNAME) ?? '';
      final permission = prefs.getString(SPK_PERMISSION_CODE) ?? '';

      setState(() {
        _userGroup = group;
        _userStaffId = staffId;
        _userName = name;
        _userNickname = nickname.isNotEmpty ? nickname : name;
        _userRole = (permission == 'SM') ? '隊長' : (permission == 'SR' ? 'SR' : '員工');
        _isSuperAdmin = (permission == 'SM');   // 隊長 = 超級管理員
        _isSR = (permission == 'SR');           // SR = 可管理自己隊
        _currentTeam = group;
        _isLoading = false;
      });
      _todayShift = ShiftCalculator.calculateShift(group, DateTime.now());
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Color _getTeamButtonColor(String team) {
    switch (team) {
      case 'A': return const Color(0xFF3F51B5);
      case 'B': return const Color(0xFFFF8F00);
      case 'C': return const Color(0xFF4CAF50);
      case 'D': return const Color(0xFF9C27B0);
      default: return Colors.indigo;
    }
  }

  void _navigateToCalendar(String team) {
    final bool canFullEdit = _isSuperAdmin || _isSR;
    Widget page;
    switch (team) {
      case 'A':
        page = FullCalendarATeam(
          staffId: _userStaffId,
          teamCode: 'A',
          canFullEdit: canFullEdit,
          isSuperAdmin: _isSuperAdmin,
        );
        break;
      case 'B':
        page = FullCalendarBTeam(
          staffId: _userStaffId,
          teamCode: 'B',
          canFullEdit: canFullEdit,
          isSuperAdmin: _isSuperAdmin,
        );
        break;
      case 'C':
        page = FullCalendarCTeam(
          staffId: _userStaffId,
          teamCode: 'C',
          canFullEdit: canFullEdit,
          isSuperAdmin: _isSuperAdmin,
        );
        break;
      case 'D':
        page = FullCalendarDTeam(
          staffId: _userStaffId,
          teamCode: 'D',
          canFullEdit: canFullEdit,
          isSuperAdmin: _isSuperAdmin,
        );
        break;
      default:
        return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFFBF7),
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
          _buildUserCard(),
          _buildAnnouncement(),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('隊伍日曆 (點擊進入)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          _buildTeamButtons(),
          const SizedBox(height: 16),
          Expanded(child: _buildMenuList()),
        ],
      ),
    );
  }

  Widget _buildUserCard() {
    return Container(
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
            child: Text(_userGroup, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('工號: $_userStaffId (暱稱: $_userNickname)', style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text('權限: $_userRole | 所屬組別: $_userGroup 隊', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncement() {
    return Container(
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
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('team_announcements')
                  .doc(_userGroup)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Text('載入公告...', style: TextStyle(color: Colors.black54));
                }
                if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                  return const Text('暫無公告', style: TextStyle(color: Colors.black54));
                }
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                final content = data?['content']?.toString() ?? '';
                if (content.isEmpty) return const Text('暫無公告', style: TextStyle(color: Colors.black54));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('最新公告', style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(content, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                  ],
                );
              },
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.orange, size: 16),
        ],
      ),
    );
  }

  Widget _buildTeamButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: ['A', 'B', 'C', 'D'].map((t) {
          return Expanded(
            child: GestureDetector(
              onTap: () => _navigateToCalendar(t),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                height: 55,
                decoration: BoxDecoration(
                  color: _getTeamButtonColor(t),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMenuList() {
    final List<Widget> menus = [];

    menus.add(_buildMenuTile(
      icon: Icons.history,
      title: '我的請假記錄',
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyLeavePage())),
    ));

    menus.add(_buildMenuTile(
      icon: Icons.cancel_presentation_outlined,
      title: '取消請假申請',
      onTap: () {},
    ));

    menus.add(_buildMenuTile(
      icon: Icons.notifications_none,
      title: '隊伍公告管理',
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AnnouncementPage(team: _userGroup, canEdit: true))),
    ));

    menus.add(_buildMenuTile(
      icon: Icons.grid_view,
      title: '桌面小工具與鬧鐘',
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DesktopWidgetsPage())),
    ));

    // SM 或 SR 都可以見到以下管理功能
    if (_isSuperAdmin || _isSR) {
      menus.add(_buildMenuTile(
        icon: Icons.gavel,
        title: '審批請假申請',
        onTap: () => Navigator.pushNamed(context, ROUTE_APPROVAL),
      ));
      menus.add(_buildMenuTile(
        icon: Icons.calendar_month_outlined,
        title: '假期與自訂節日管理',
        onTap: () => Navigator.pushNamed(context, ROUTE_HOLIDAYS),
      ));
      menus.add(_buildMenuTile(
        icon: Icons.settings,
        title: 'Google Sheets 配置',
        onTap: () => Navigator.pushNamed(context, ROUTE_GOOGLE_SHEETS_CONFIG),
      ));
      menus.add(_buildMenuTile(
        icon: Icons.chat_bubble_outline,
        title: 'WhatsApp 通知配置',
        onTap: () => Navigator.pushNamed(context, ROUTE_WHATSAPP_CONFIG),
      ));
    }

    return ListView(children: menus);
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