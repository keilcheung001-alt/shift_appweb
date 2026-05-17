import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/constants.dart';
import 'announcement_page.dart'; // 🟢 讓通告成為核心
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
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  // 🟢 核心跳轉邏輯：撳 A、B、C、D 隊，即時帶你跳轉去原本睇到邊個請假嘅「大表」！
  void _navigateToFullCalendar(BuildContext context, String teamCode) {
    String routeName;
    switch (teamCode) {
      case 'A': routeName = ROUTE_CALENDAR_A; break;
      case 'B': routeName = ROUTE_CALENDAR_B; break;
      case 'C': routeName = ROUTE_CALENDAR_C; break;
      case 'D': routeName = ROUTE_CALENDAR_D; break;
      default: routeName = ROUTE_CALENDAR_A;
    }

    Navigator.pushNamed(
      context,
      routeName,
      arguments: {
        'staffId': widget.staffId,
        'teamCode': teamCode,
        'canFullEdit': widget.canFullEdit,
        'isSuperAdmin': widget.isSuperAdmin,
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 🟢 判斷是否為管理員
    final bool isAdmin = widget.role == 'admin' || (widget.canFullEdit ?? false) || (widget.isSuperAdmin ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('廠房排班與管理系統'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
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
            // 🟢 1. 頂部：四大隊伍大表跳轉按鈕（原本最核心的功能，撳咗即轉去睇邊個請假嘅大表）
            const Text(
              '進入各隊排班大表 (可查看請假與個人設定)：',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['A', 'B', 'C', 'D'].map((team) {
                return SizedBox(
                  width: 75,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentTeam == team ? Colors.orange : Colors.blueGrey.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 3,
                    ),
                    onPressed: () => _navigateToFullCalendar(context, team),
                    child: Text('$team 隊', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // 🟢 2. 中部：原本一入去就應該見到嘅「通告版面」！內嵌進來，讓你可以直接看、直接篇！
            const Text(
              '📢 廠房最新公告',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: SizedBox(
                height: 450, // 給予充足的空間直接顯示與操作通告
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AnnouncementPage(
                    team: _currentTeam,
                    canEdit: isAdmin, // 連動權限，如果是管理員才可以進行編輯/發佈
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}