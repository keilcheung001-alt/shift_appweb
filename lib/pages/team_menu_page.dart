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
  String _authStatus = '載入中...';
  String _selectedGroup = 'A';
  final List<String> _announcements = [];
  StreamSubscription? _announcementSub;

  @override
  void initState() {
    super.initState();
    _loadAuth();
    _loadSelectedGroup();
    _fetchAnnouncements();

    // 🎯 核心修改一：不論是管理員還是普通隊員，一進主選單，背後全自動加載 2026 公眾假期
    // 這樣普通隊員點進月曆時，紅日變色數據一早就在本地緩存好了，必定自動變色！
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        HolidaysPage.downloadHolidaysForYear(2026);
        print("【系統提示】已成功為當前帳號背景加載 2026 假期變色數據");
      } catch (e) {
        print("背景自動加載假期失敗: $e");
      }
    });
  }

  @override
  void dispose() {
    _announcementSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAuth() async {
    setState(() {
      if (widget.isSuperAdmin) {
        _authStatus = '權限: 隊長 (SM)';
      } else if (widget.canFullEdit) {
        _authStatus = '權限: 管理員 (SR)';
      } else {
        _authStatus = '權限: 普通隊員';
      }
    });
  }

  Future<void> _loadSelectedGroup() async {
    setState(() {
      _selectedGroup = widget.group;
    });
  }

  void _fetchAnnouncements() {
    _announcementSub = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('timestamp', descending: true)
        .limit(3)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _announcements.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['content'] != null) {
            _announcements.add(data['content'].toString());
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tempo Leave 主功能選單'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 使用者資訊卡片
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.indigo.shade100,
                      child: Icon(Icons.person, size: 36, color: Colors.indigo.shade800),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('員工編號: ${widget.staffId}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('預設隊伍: ${widget.group} 隊', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(_authStatus, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 公告欄
            const Text('📢 最新公告', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_announcements.isEmpty)
              const Card(child: ListTile(title: Text('目前沒有公告', style: TextStyle(color: Colors.grey))))
            else
              ..._announcements.map((msg) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(leading: const Icon(Icons.campaign, color: Colors.amber), title: Text(msg)),
                  )),
            const SizedBox(height: 24),

            // 四個隊伍日曆大網格按鈕
            const Text('📅 檢視隊伍更表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _buildTeamButton('A 隊', Colors.red.shade700, 'A'),
                _buildTeamButton('B 隊', Colors.blue.shade700, 'B'),
                _buildTeamButton('C 隊', Colors.green.shade700, 'C'),
                _buildTeamButton('D 隊', Colors.orange.shade700, 'D'),
              ],
            ),
            const SizedBox(height: 24),

            // 功能選單列表
            const Text('⚙️ 核心功能', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: Column(
                children: [
                  _buildSettingTile(Icons.add_task, '提交請假申請', () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => MyLeavePage(staffId: widget.staffId)));
                  }),
                  _buildSettingTile(Icons.cancel_presentation, '取消請假申請', () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => CancelLeaveRequestPage(staffId: widget.staffId)));
                  }),
                  if (widget.canFullEdit || widget.isSuperAdmin) ...[
                    const Divider(height: 1),
                    _buildSettingTile(Icons.fact_check, '審批假期管理', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const ApprovalPage()));
                    }),
                    _buildSettingTile(Icons.edit_calendar, '設定公眾假期數據', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const HolidaysPage()));
                    }),
                    _buildSettingTile(Icons.rate_review, '發布與管理公告', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AnnouncementPage()));
                    }),
                    _buildSettingTile(Icons.cloud_sync, 'Google Sheets 同步設定', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const GoogleSheetsConfigPage()));
                    }),
                    _buildSettingTile(Icons.chat, 'WhatsApp 自動通知設定', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const WhatsappConfigPage()));
                    }),
                  ],
                  const Divider(height: 1),
                  _buildSettingTile(Icons.widgets, '手機桌面小工具與鬧鐘設定', () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const DesktopWidgetsPage()));
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamButton(String label, Color color, String teamCode) {
    return InkWell(
      onTap: () => _navToCalendar(teamCode),
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

    // 🎯 核心修改二：在點擊進入月曆的瞬間，外層套上「手勢放大鏡」 (InteractiveViewer)
    // 🔒 minScale 鎖死在 1.0 (就是你現在預設最完美的畫面大小，不允許再縮小變芝麻，也不會讓版面空掉)
    // 🟢 maxScale 設為 3.0 (需要看字時，雙指一拉隨時放大 3 倍，看完縮回去 1.0 就卡住還原)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InteractiveViewer(
          panEnabled: true,    // 允許手指四個方向拖動畫面
          scaleEnabled: true,  // 啟用雙指手勢
          minScale: 1.0,       // 鎖死最低下限，不准縮小
          maxScale: 3.0,       // 允許最大放大的上限
          child: target,
        ),
      ),
    );
  }

  Widget _buildSettingTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.indigo.shade700),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}