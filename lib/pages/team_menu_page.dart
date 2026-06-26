// lib/pages/team_menu_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzData;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/shift_calculator.dart';
import '../constants/constants.dart';
import 'my_leave_page.dart';
import 'announcement_page.dart';
import 'desktop_widgets_page.dart';
import 'cancel_leave_request_page.dart';
import 'staff_quota_page.dart';
import 'full_calendar_a.dart';
import 'full_calendar_b.dart';
import 'full_calendar_c.dart';
import 'full_calendar_d.dart';
import 'holidays_page.dart';  // 👈 加入 HolidaysPage import

class TeamMenuPage extends StatefulWidget {
  const TeamMenuPage({super.key});

  @override
  State<TeamMenuPage> createState() => _TeamMenuPageState();
}

class _TeamMenuPageState extends State<TeamMenuPage> {
  String _currentTeam = 'A';
  String _todayShift = '?班';
  String _userName = '';
  String _userNickname = '';
  String _userStaffId = '';
  String _userRole = '員工';
  String _userGroup = 'A';
  bool _isLoading = true;
  bool _isSuperAdmin = false;
  bool _isSR = false;

  final MethodChannel _calendarChannel = const MethodChannel('calendar_channel');
  final MethodChannel _alarmChannel = const MethodChannel('com.example.shift_app/alarm');

  @override
  void initState() {
    super.initState();
    tzData.initializeTimeZones();
    _loadUserData();
  }

  Future<void> _refreshAlarms() async {
    try {
      await _alarmChannel.invokeMethod('refreshAlarms', {'team': _userGroup});
    } catch (e) {
      debugPrint("Error: $e");
    }
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
        _isSuperAdmin = (permission == 'SM');
        _isSR = (permission == 'SR');
        _currentTeam = group;
        _isLoading = false;
      });
      _todayShift = ShiftCalculator.calculateShift(group, DateTime.now());
      await _refreshAlarms();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// 揀邊個 team 嘅 ICS（Download ICS 用）
  Future<void> _showTeamSelectionForICS() async {
    final selectedTeam = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('選擇隊伍'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['A', 'B', 'C', 'D'].map((team) => ListTile(
            title: Text('$team 隊'),
            onTap: () => Navigator.pop(ctx, team),
          )).toList(),
        ),
      ),
    );
    if (selectedTeam != null) {
      await _generateAndShareICS(selectedTeam);
    }
  }

  Future<void> _generateAndShareICS(String teamCode) async {
    setState(() => _isLoading = true);
    try {
      final StringBuffer buffer = StringBuffer();
      buffer.writeln("BEGIN:VCALENDAR");
      buffer.writeln("VERSION:2.0");
      buffer.writeln("PRODID:-//ShiftApp//EN");
      buffer.writeln("CALSCALE:GREGORIAN");
      buffer.writeln("METHOD:PUBLISH");

      final DateTime today = DateTime.now();
      for (int i = 0; i < 30; i++) {
        final DateTime targetDate = today.add(Duration(days: i));
        final String shiftCode = ShiftCalculator.calculateShift(teamCode, targetDate);
        if (ShiftCalculator.isRestDay(shiftCode)) continue;

        String timeRange = ShiftCalculator.getShiftTime(shiftCode);
        List<String> times = timeRange.split('-');
        String startTime = times[0].replaceAll(':', '') + "00";
        String endTime = times[1].replaceAll(':', '') + "00";

        String dateStr = "${targetDate.year}${targetDate.month.toString().padLeft(2, '0')}${targetDate.day.toString().padLeft(2, '0')}";
        buffer.writeln("BEGIN:VEVENT");
        buffer.writeln("SUMMARY:Shift: ${ShiftCalculator.getShiftName(shiftCode)}");
        buffer.writeln("DTSTART:${dateStr}T$startTime");
        buffer.writeln("DTEND:${dateStr}T$endTime");
        buffer.writeln("TRANSP:OPAQUE");
        buffer.writeln("END:VEVENT");
      }
      buffer.writeln("END:VCALENDAR");

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/shift_${teamCode}.ics');
      await file.writeAsString(buffer.toString());
      await Share.shareXFiles([XFile(file.path)], text: 'Schedule for ${teamCode} Team');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToCalendar(String team) {
    final bool canFullEdit = _isSuperAdmin || _isSR;
    Widget page;
    switch (team) {
      case 'A': page = FullCalendarATeam(staffId: _userStaffId, teamCode: 'A', canFullEdit: canFullEdit, isSuperAdmin: _isSuperAdmin); break;
      case 'B': page = FullCalendarBTeam(staffId: _userStaffId, teamCode: 'B', canFullEdit: canFullEdit, isSuperAdmin: _isSuperAdmin); break;
      case 'C': page = FullCalendarCTeam(staffId: _userStaffId, teamCode: 'C', canFullEdit: canFullEdit, isSuperAdmin: _isSuperAdmin); break;
      case 'D': page = FullCalendarDTeam(staffId: _userStaffId, teamCode: 'D', canFullEdit: canFullEdit, isSuperAdmin: _isSuperAdmin); break;
      default: return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: const Color(0xFFFFFBF7), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(title: const Text('Menu'), backgroundColor: const Color(0xFF4A55A2), foregroundColor: Colors.white, actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => Navigator.pushReplacementNamed(context, ROUTE_LOGIN))]),
      body: Column(
        children: [
          _buildUserCard(),
          _buildAnnouncement(),
          const SizedBox(height: 16),
          _buildTeamButtons(),
          Expanded(child: _buildMenuList()),
        ],
      ),
    );
  }

  Widget _buildUserCard() {
    return Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF3F51B5), borderRadius: BorderRadius.circular(24)), child: Row(children: [CircleAvatar(radius: 28, backgroundColor: Colors.white.withOpacity(0.2), child: Text(_userGroup, style: const TextStyle(color: Colors.white, fontSize: 24))), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_userName, style: const TextStyle(color: Colors.white, fontSize: 20)), Text('ID: $_userStaffId', style: const TextStyle(color: Colors.white, fontSize: 13))]))]));
  }

  Widget _buildAnnouncement() {
    return Container(width: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 16), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(16)), child: StreamBuilder<DocumentSnapshot>(stream: FirebaseFirestore.instance.collection('team_announcements').doc(_userGroup).snapshots(), builder: (context, snapshot) {
      if (!snapshot.hasData || !snapshot.data!.exists) return const Text('No announcement');
      final data = snapshot.data!.data() as Map<String, dynamic>;
      return Text(data['content'] ?? 'No announcement');
    }));
  }

  Widget _buildTeamButtons() {
    return Padding(padding: const EdgeInsets.all(16), child: Row(children: ['A', 'B', 'C', 'D'].map((t) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: SizedBox(height: 80, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _getTeamButtonColor(t), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: () => _navigateToCalendar(t), child: Text(t, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white))))))).toList()));
  }

  Widget _buildMenuList() {
    return ListView(
      children: [
        _buildMenuTile(Icons.history, 'Leave Records', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyLeavePage())), Colors.blue.shade100, Colors.blue.shade900),
        _buildMenuTile(Icons.cancel, 'Cancel Leave', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CancelLeaveRequestPage())), Colors.red.shade100, Colors.red.shade900),
        _buildMenuTile(Icons.grid_view, 'Widgets & Alarms', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DesktopWidgetsPage())), Colors.orange.shade100, Colors.orange.shade900),

        // 👇 加入假期管理入口
        _buildMenuTile(
            Icons.calendar_today,
            '假期管理',
                () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HolidaysPage())
            ),
            Colors.pink.shade100,
            Colors.pink.shade900
        ),

        _buildMenuTile(Icons.file_download, 'Download ICS', _showTeamSelectionForICS, Colors.grey.shade200, Colors.black87),

        // 調整員工假期配額（管理員先見到）
        if (_isSuperAdmin || _isSR)
          _buildMenuTile(Icons.edit, '調整員工假期', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const StaffQuotaPage())), Colors.teal.shade100, Colors.teal.shade900),

        if (_isSuperAdmin || _isSR) ...[
          _buildMenuTile(Icons.gavel, 'Approve Leave', () => Navigator.pushNamed(context, ROUTE_APPROVAL), Colors.purple.shade100, Colors.purple.shade900),
          _buildMenuTile(Icons.campaign, 'Announcements', () => Navigator.push(context, MaterialPageRoute(builder: (context) => AnnouncementPage(team: _userGroup, canEdit: true))), Colors.amber.shade100, Colors.amber.shade900),
        ],
      ],
    );
  }

  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap, Color bgColor, Color textColor) {
    return Container(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)), child: ListTile(leading: Icon(icon, color: textColor), title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)), trailing: Icon(Icons.chevron_right, color: textColor), onTap: onTap));
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
}