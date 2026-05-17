import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/constants.dart';
import 'announcement_page.dart';
import 'whatsapp_config_page.dart';
import 'my_leave_page.dart';
import 'cancel_leave_request_page.dart';
import '../screens/login_page.dart';

// 🎨 【四條 Team 專屬顏色設定區】—— 100% 跟隨你的原底顏色設定
// 如果顏色想微調，直接修改後面的 Colors 即可
const Color COLOR_TEAM_A = Colors.red;         // 🔴 A 隊專屬色
const Color COLOR_TEAM_B = Colors.green;       // 🟢 B 隊專屬色
const Color COLOR_TEAM_C = Colors.blue;        // 🔵 C 隊專屬色
const Color COLOR_TEAM_D = Colors.purple;      // 🟣 D 隊專屬色

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

  // 🟢 安全登出：只刪除登入狀態，保留所有人名、代號和 Staff ID，下次免重複輸入
  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove(SPK_ROLE);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  // 🎨 獲取每條 Team 專屬按鈕顏色的邏輯
  Color _getTeamColor(String teamCode) {
    switch (teamCode) {
      case 'A': return COLOR_TEAM_A;
      case 'B': return COLOR_TEAM_B;
      case 'C': return COLOR_TEAM_C;
      case 'D': return COLOR_TEAM_D;
      default: return Colors.orange;
    }
  }

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
            // 📅 1. 四大隊伍大表入口（完美跟隨各自隊伍專屬色，撳入去即看請假大表格與個人鬧鐘）
            const Text(
              '進入各隊排班大表 (可設定個人鬧鐘與查看請假)：',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['A', 'B', 'C', 'D'].map((team) {
                final teamColor = _getTeamColor(team);
                return SizedBox(
                  width: 75,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: teamColor, // 🟢 100% 帶入該隊伍專屬代表色
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

            // ⚙️ 2. 中部：管理員功能表（正宗 8 樣功能全齊）
            const Text('⚙️ 系統管理功能選單 (八大核心功能)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.calendar_month, color: Colors.redAccent),
                    title: const Text('1. 廠房紅日公眾假期設定'),
                    onTap: () => Navigator.pushNamed(context, ROUTE_HOLIDAYS),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.chat, color: Colors.green),
                    title: const Text('2. 通知群組設定 (WhatsApp)'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WhatsAppConfigPage())),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.gavel, color: Colors.purple),
                    title: const Text('3. 員工請假審批管理中心'),
                    onTap: () => Navigator.pushNamed(context, ROUTE_APPROVAL),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.assignment, color: Colors.orange),
                    title: const Text('4. 我的請假記錄'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyLeavePage())),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cancel, color: Colors.red),
                    title: const Text('5. 取消請假申請'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CancelLeaveRequestPage())),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.phone_android, color: Colors.blue),
                    title: const Text('6. 手機小程式與小工具資料同步設定 (鬧鐘/快照更新)'),
                    onTap: () => Navigator.pushNamed(context, ROUTE_DESKTOP_WIDGETS),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.table_chart, color: Colors.teal),
                    title: const Text('7. Google Sheets 數據對接配置'),
                    onTap: () => Navigator.pushNamed(context, ROUTE_GOOGLE_SHEETS_CONFIG),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.camera_alt, color: Colors.brown),
                    title: const Text('8. 廠房更表網頁快照匯出'),
                    onTap: () => Navigator.pushNamed(context, ROUTE_SNAPSHOT_WRITER),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 📢 3. 底部：公告版面
            const Text('📢 廠房最新公告', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: SizedBox(
                height: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AnnouncementPage(
                    team: _currentTeam,
                    canEdit: widget.role == 'admin' || (widget.canFullEdit ?? false) || (widget.isSuperAdmin ?? false),
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