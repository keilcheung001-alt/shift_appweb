import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shift_app/constants/constants.dart';
import 'package:shift_app/utils/auth_util.dart';
import 'package:shift_app/pages/full_calendar_a.dart';
import 'package:shift_app/pages/full_calendar_b.dart';
import 'package:shift_app/pages/full_calendar_c.dart';
import 'package:shift_app/pages/full_calendar_d.dart';
import 'package:shift_app/pages/approval_page.dart';
import 'package:shift_app/pages/my_leave_page.dart';
import 'package:shift_app/pages/cancel_leave_request_page.dart';
import 'package:shift_app/pages/holidays_page.dart';
import 'package:shift_app/pages/whatsapp_config_page.dart';
import 'package:shift_app/pages/google_sheets_config_page.dart';
import 'package:shift_app/pages/desktop_widgets_page.dart';
import 'package:shift_app/pages/announcement_page.dart';

class TeamMenuPage extends StatefulWidget {
  final String staffId;
  final String group;
  final bool canFullEdit;
  final bool isSuperAdmin;

  const TeamMenuPage({
    super.key,
    required this.staffId,
    required this.group,
    required this.canFullEdit,
    required this.isSuperAdmin,
  });

  @override
  State<TeamMenuPage> createState() => _TeamMenuPageState();
}

class _TeamMenuPageState extends State<TeamMenuPage> {
  String _userName = '載入中...';
  String _userNickname = '';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final name = await AuthUtil.getMyName();
    final nickname = await AuthUtil.getNickname();
    setState(() {
      _userName = name;
      _userNickname = nickname;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隊伍管理選單'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthUtil.logout();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  ROUTE_LOGIN,
                      (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 使用者資訊卡片
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.indigo, Colors.blueAccent]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white24,
                  child: Text(widget.group, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_userName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(
                        '工號: ${widget.staffId}${_userNickname.isNotEmpty ? ' (暱稱: $_userNickname)' : ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 公告橫幅（可滾動，最多顯示約4行高度）
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('team_announcements').doc(widget.group).snapshots(),
            builder: (context, snapshot) {
              String content = "點擊查看詳情...";
              if (snapshot.hasData && snapshot.data!.exists) {
                content = snapshot.data!['content'] ?? "暫無公告內容";
              }
              return InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => AnnouncementPage(team: widget.group, canEdit: widget.canFullEdit))),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.campaign, color: Colors.orange),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 80),
                          child: SingleChildScrollView(
                            child: Text(
                              content,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_right, color: Colors.orange),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          const Text('隊伍日曆 (快速切換)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _buildGridItem('A', Colors.indigo, () => _navToCalendar('A')),
              _buildGridItem('B', Colors.orange.shade700, () => _navToCalendar('B')),
              _buildGridItem('C', Colors.green.shade700, () => _navToCalendar('C')),
              _buildGridItem('D', Colors.purple.shade700, () => _navToCalendar('D')),
            ],
          ),
          const SizedBox(height: 32),

          const Text('功能選單', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),

          _buildSettingTile(Icons.history, '我的請假記錄', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyLeavePage()))),
          _buildDivider(),
          _buildSettingTile(Icons.cancel_presentation, '取消請假申請', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CancelLeaveRequestPage()))),
          _buildDivider(),
          _buildSettingTile(Icons.notification_important_outlined, '隊伍公告管理', () => Navigator.push(context, MaterialPageRoute(builder: (c) => AnnouncementPage(team: widget.group, canEdit: widget.canFullEdit)))),
          _buildDivider(),
          _buildSettingTile(Icons.widgets_outlined, '桌面小工具與鬧鐘', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DesktopWidgetsPage()))),
          _buildDivider(),

          if (widget.canFullEdit) ...[
            const SizedBox(height: 32),
            const Text('管理員功能', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            const SizedBox(height: 8),
            _buildSettingTile(Icons.how_to_reg, '審批請假申請', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ApprovalPage()))),
            _buildDivider(),
            _buildSettingTile(Icons.event_note, '假期與自訂節日管理', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HolidaysPage()))),
            _buildDivider(),
            _buildSettingTile(Icons.settings_suggest, 'Google Sheets 配置', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GoogleSheetsConfigPage()))),
            _buildDivider(),
            _buildSettingTile(Icons.chat_outlined, 'WhatsApp 通知配置', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WhatsAppConfigPage()))),
            _buildDivider(),
          ],
        ],
      ),
    );
  }

  Widget _buildGridItem(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Center(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
      ),
    );
  }

  void _navToCalendar(String team) {
    Widget target;
    switch (team) {
      case 'B':
        target = FullCalendarBTeam(staffId: widget.staffId, canFullEdit: widget.canFullEdit, isSuperAdmin: widget.isSuperAdmin);
        break;
      case 'C':
        target = FullCalendarCTeam(staffId: widget.staffId, canFullEdit: widget.canFullEdit, isSuperAdmin: widget.isSuperAdmin);
        break;
      case 'D':
        target = FullCalendarDTeam(staffId: widget.staffId, canFullEdit: widget.canFullEdit, isSuperAdmin: widget.isSuperAdmin);
        break;
      default:
        target = FullCalendarATeam(staffId: widget.staffId, teamCode: 'A', canFullEdit: widget.canFullEdit, isSuperAdmin: widget.isSuperAdmin);
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => target));
  }

  Widget _buildSettingTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.indigo.shade700),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildDivider() => const Divider(height: 1, indent: 50);
}