import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'desktop_widgets_page.dart';
import 'full_calendar_a.dart';
import 'full_calendar_b.dart';
import 'full_calendar_c.dart';
import 'full_calendar_d.dart';
import '../constants/constants.dart';

class TeamMenuPage extends StatefulWidget {
  const TeamMenuPage({super.key});

  @override
  State<TeamMenuPage> createState() => _TeamMenuPageState();
}

class _TeamMenuPageState extends State<TeamMenuPage> {
  String _staffId = '';
  String _myGroup = 'A';
  bool _isSuperAdmin = false;
  bool _canFullEdit = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _staffId = prefs.getString(SPK_STAFF_ID) ?? '';
      _myGroup = prefs.getString(SPK_GROUP) ?? 'A';

      _isSuperAdmin = (_staffId == 'admin' || _staffId == '666666');
      _canFullEdit = _isSuperAdmin || (_staffId == '888888');
      _loading = false;
    });
  }

  void _navigateToTeamCalendar(String teamCode) {
    Widget targetPage;
    switch (teamCode) {
      case 'A':
        targetPage = FullCalendarATeam(staffId: _staffId, canFullEdit: _canFullEdit, isSuperAdmin: _isSuperAdmin);
        break;
      case 'B':
        targetPage = FullCalendarBTeam(staffId: _staffId, canFullEdit: _canFullEdit, isSuperAdmin: _isSuperAdmin);
        break;
      case 'C':
        targetPage = FullCalendarCTeam(staffId: _staffId, canFullEdit: _canFullEdit, isSuperAdmin: _isSuperAdmin);
        break;
      case 'D':
        targetPage = FullCalendarDTeam(staffId: _staffId, canFullEdit: _canFullEdit, isSuperAdmin: _isSuperAdmin);
        break;
      default:
        return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => targetPage),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final Map<String, Color> teamColors = {
      'A': Colors.blue.shade700,
      'B': Colors.green.shade700,
      'C': Colors.purple.shade700,
      'D': Colors.orange.shade700,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('廠房團隊選單'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_alarm),
            tooltip: '小工具與鬧鐘設定', // ⚙️ 精準修復：由 title 改回正確的 tooltip
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DesktopWidgetsPage()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.grey.shade50,
              elevation: 1,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: teamColors[_myGroup] ?? Colors.orange,
                  child: Text(_myGroup, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: Text('員工編號: $_staffId', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('主要所屬組別: $_myGroup 隊 ${_isSuperAdmin ? " (超級管理員)" : ""}'),
                trailing: const Icon(Icons.verified_user, color: Colors.green),
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              '📅 檢視各隊請假排班行事曆',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: ['A', 'B', 'C', 'D'].map((team) {
                final bool isMyTeam = (team == _myGroup);
                return InkWell(
                  onTap: () => _navigateToTeamCalendar(team),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isMyTeam ? teamColors[team]!.withOpacity(0.08) : Colors.white,
                      border: Border.all(
                        color: isMyTeam ? teamColors[team]! : Colors.grey.shade300,
                        width: isMyTeam ? 2.0 : 1.0,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$team 隊行事曆',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: teamColors[team],
                              ),
                            ),
                            if (isMyTeam)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: teamColors[team],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('我屬隊伍', style: TextStyle(color: Colors.white, fontSize: 10)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '點擊查看 $team 隊成員請假詳情、審批進度及即時更新。',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            const Text(
              '⚙️ 系統設定與工具',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.tune, color: Colors.orange),
                title: const Text('桌面小工具與全彈性鬧鐘'),
                subtitle: const Text('設定 5 班次獨立開關、0-240 分鐘出行提前響鬧'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DesktopWidgetsPage()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}