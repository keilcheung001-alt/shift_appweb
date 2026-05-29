
// lib/pages/team_menu_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../utils/shift_calculator.dart';
import '../constants/constants.dart';
import 'my_leave_page.dart';
import 'announcement_page.dart';
import 'desktop_widgets_page.dart';
import 'cancel_leave_request_page.dart';
import 'approval_page.dart';
import 'holidays_page.dart';
import 'google_sheets_config_page.dart';
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
  String _todayShift = '?班';
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
      final staffId = prefs.getString(SPK_STAFF_ID) ?? '';
      final permissionCode = prefs.getString(SPK_PERMISSION_CODE) ?? '';
      final savedGroup = prefs.getString(SPK_GROUP) ?? 'A';

      if (staffId.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final doc = await FirebaseFirestore.instance.collection('users').doc(staffId).get();
      if (doc.exists) {
        final data = doc.data()!;
        _userName = data['name'] ?? '';
        _userNickname = data['nickname'] ?? '';
        _userStaffId = staffId;
        _userGroup = data['group'] ?? savedGroup;
        _currentTeam = _userGroup;

        _isSuperAdmin = (permissionCode == PERMISSION_CODE_SUPER_ADMIN);
        _isSR = (permissionCode == PERMISSION_CODE_TEAM_LEAD);

        if (_isSuperAdmin) {
          _userRole = '超級管理員 (SM)';
        } else if (_isSR) {
          _userRole = '隊長 (SR)';
        } else {
          _userRole = '廠房員工';
        }
      }

      _todayShift = ShiftCalculator.calculateShift(_currentTeam, DateTime.now());

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('加載用戶選單失敗: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 💡 獨立彈窗：將配置功能收納，不污染主畫面
  void _showNativeAlarmAssistantDialog() {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.alarm, color: Color(0xFF1A237E)),
              SizedBox(width: 8),
              Text('手機原生出門提示助手', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            '系統會為您將 [$_currentTeam 隊] 未來 28 天的班次自動打包成「系統重複性系列事件」寫入手機日曆。\n\n手機會跟隨 28 日週期在相應的返工日子自動響鬧，保留最高走盞自由度！',
            style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700, side: BorderSide(color: Colors.red.shade300)),
              onPressed: () {
                Navigator.of(ctx).pop();
                _showClearConfirmationDialog();
              },
              child: const Text('一鍵清空系列'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E)),
              onPressed: () {
                Navigator.of(ctx).pop();
                _injectShiftGroupsToNative();
              },
              child: const Text('一鍵配置28日循環', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // 🔄 真正利用 Android 系統重複事件機制 (RRULE) 配置 28 天週期
  Future<void> _injectShiftGroupsToNative() async {
    try {
      final now = DateTime.now();
      // 從今天或明天開始計算核心28天區間
      final startDate = DateTime(now.year, now.month, now.day);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在啟動 Android 系統日曆，打包 $_currentTeam 隊 28 天週期規律...'), backgroundColor: Colors.indigo),
      );

      List<Map<String, dynamic>> shiftGroups = [];
      String currentShiftType = '';
      DateTime? groupStartTime;
      int currentGroupCount = 0;

      for (int i = 0; i < 28; i++) {
        final checkDate = startDate.add(Duration(days: i));
        final shiftCode = ShiftCalculator.calculateShift(_currentTeam, checkDate);
        final isWorking = shiftCode.isNotEmpty && shiftCode != 'REST';

        if (isWorking) {
          if (shiftCode == currentShiftType) {
            currentGroupCount++;
          } else {
            if (currentShiftType.isNotEmpty && groupStartTime != null) {
              shiftGroups.add({
                'shiftCode': currentShiftType,
                'startTime': groupStartTime,
                'count': currentGroupCount,
              });
            }
            currentShiftType = shiftCode;
            groupStartTime = checkDate;
            currentGroupCount = 1;
          }
        } else {
          if (currentShiftType.isNotEmpty && groupStartTime != null) {
            shiftGroups.add({
              'shiftCode': currentShiftType,
              'startTime': groupStartTime,
              'count': currentGroupCount,
            });
          }
          currentShiftType = '';
          groupStartTime = null;
          currentGroupCount = 0;
        }
      }

      if (currentShiftType.isNotEmpty && groupStartTime != null) {
        shiftGroups.add({
          'shiftCode': currentShiftType,
          'startTime': groupStartTime,
          'count': currentGroupCount,
        });
      }

      if (shiftGroups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('計算完成：未來 28 天全為休息日，無需注入。'), backgroundColor: Colors.orange),
        );
        return;
      }

      // 依次將各個連續返工的區塊以系統日曆「重複事件 (FREQ=DAILY;COUNT=X)」方式塞入手機，讓手機日曆自己數日子響
      for (var group in shiftGroups) {
        final String code = group['shiftCode'];
        final DateTime sTime = group['startTime'];
        final int count = group['count'];

        final shiftName = ShiftCalculator.getShiftName(code);
        final shiftTimeStr = ShiftCalculator.getShiftTime(code);

        int startHour = 7;
        int startMin = 0;
        if (shiftTimeStr.contains(':')) {
          try {
            final firstPart = shiftTimeStr.split('-').first.trim();
            startHour = int.parse(firstPart.split(':').first);
            startMin = int.parse(firstPart.split(':').last);
          } catch (_) {}
        }

        final eventStartTime = DateTime(sTime.year, sTime.month, sTime.day, startHour - 1, startMin);
        final eventEndTime = eventStartTime.add(const Duration(minutes: 30));

        // ⚙️ 核心修復：這行傳遞給手機日曆，告訴它這是重複事件系列（連響 count 天），手機會自動接管！
        final String rrule = "FREQ=DAILY;COUNT=$count";

        final AndroidIntent intent = AndroidIntent(
          action: 'android.intent.action.INSERT',
          data: 'content://com.android.calendar/events',
          type: 'vnd.android.cursor.dir/event',
          arguments: <String, dynamic>{
            'title': '⚙️ [$_currentTeam隊: $shiftName出門提示]',
            'description': '大埔廠房更表助手：今日返 $shiftName ($shiftTimeStr)。此為28日週期自動重複事件系列。',
            'beginTime': eventStartTime.millisecondsSinceEpoch,
            'endTime': eventEndTime.millisecondsSinceEpoch,
            'rrule': rrule,
            'hasAlarm': 1,
          },
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );

        await intent.launch();
        await Future.delayed(const Duration(milliseconds: 700));
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ $_currentTeam 隊 28日週期提示已成功推送至手機，請在彈出的系統日曆中儲存系列事件。'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('調用手機系統失敗：$e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showClearConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('確定要清空提示系列嗎？', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            '此動作將引導您前往手機系統日曆，去徹底抹除之前配置的 $_currentTeam 隊全體重複提示系列。\n\n是否確定前往日曆清除？',
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () {
                Navigator.of(ctx).pop();
                _launchNativeCalendarToClear();
              },
              child: const Text('確認清除', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchNativeCalendarToClear() async {
    try {
      final AndroidIntent intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: 'content://com.android.calendar/time',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已為您打開系統日曆。請點擊帶有 ⚙️ 標籤的更表提示，選擇「刪除」並點選「刪除此系列的所有事件」即可完美還原手機！'),
          backgroundColor: Colors.blueGrey,
          duration: Duration(seconds: 6),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法打開系統日曆：$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final todayStr = ShiftCalculator.getShiftName(_todayShift);
    final todayTimeStr = ShiftCalculator.getShiftTime(_todayShift);

    return Scaffold(
      appBar: AppBar(
        title: const Text('大埔生產廠房選單', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: Column(
        children: [
          // 🛡️ 1. 完全回復原汁原味的原生頂部個人資料卡，絕不佔用額外空間
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '歡迎返工, $_userName ($_userNickname)',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('身分: $_userRole  |  所屬隊伍: $_userGroup 隊', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const Divider(color: Colors.white24, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('今日更表提示 ($_currentTeam 隊):', style: const TextStyle(color: Colors.white, fontSize: 14)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ShiftCalculator.getShiftColor(_todayShift),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$todayStr ($todayTimeStr)',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 🛡️ 2. 原版四隊切換 ChoiceChips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['A', 'B', 'C', 'D'].map((team) {
                final isSelected = _currentTeam == team;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Container(
                        alignment: Alignment.center,
                        child: Text('$team 隊', style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFF3F51B5),
                      backgroundColor: Colors.grey.shade200,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _currentTeam = team;
                            _todayShift = ShiftCalculator.calculateShift(_currentTeam, DateTime.now());
                          });
                        }
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // 🛡️ 3. 下方功能選單清單（廠房重要公告完美留守，位置顯眼！）
          Expanded(
            child: _buildMenuListView(),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuListView() {
    List<Widget> menus = [];

    // 1. 查看完整團隊日曆
    menus.add(_buildMenuTile(
      icon: Icons.calendar_month,
      title: '查看完整團隊日曆 ($_currentTeam 隊)',
      onTap: () {
        Widget targetCalendar;
        if (_currentTeam == 'A') {
          targetCalendar = FullCalendarATeam(staffId: _userStaffId, canFullEdit: _isSuperAdmin || (_isSR && _userGroup == 'A'), isSuperAdmin: _isSuperAdmin);
        } else if (_currentTeam == 'B') {
          targetCalendar = FullCalendarBTeam(staffId: _userStaffId, canFullEdit: _isSuperAdmin || (_isSR && _userGroup == 'B'), isSuperAdmin: _isSuperAdmin);
        } else if (_currentTeam == 'C') {
          targetCalendar = FullCalendarCTeam(staffId: _userStaffId, canFullEdit: _isSuperAdmin || (_isSR && _userGroup == 'C'), isSuperAdmin: _isSuperAdmin);
        } else {
          targetCalendar = FullCalendarDTeam(staffId: _userStaffId, canFullEdit: _isSuperAdmin || (_isSR && _userGroup == 'D'), isSuperAdmin: _isSuperAdmin);
        }
        Navigator.push(context, MaterialPageRoute(builder: (context) => targetCalendar));
      },
    ));

    // 📢 2. 查看廠房重要公告 (原汁原味，絕不被遮擋！)
    menus.add(_buildMenuTile(
      icon: Icons.campaign,
      title: '查看廠房重要公告',
      iconColor: Colors.red.shade700,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AnnouncementPage(
        team: _currentTeam,
        canEdit: _isSuperAdmin || (_isSR && _userGroup == _currentTeam),
      ))),
    ));

    // 💡 3. 手機原生出門提示助手 (全新改版：收納成一個乾淨的按鈕 Tile，撳入去先會彈窗處理)
    menus.add(_buildMenuTile(
      icon: Icons.alarm_add,
      title: '設定手機日曆出門提示 (28日自動重複規律)',
      iconColor: Colors.green.shade700,
      backgroundColor: Colors.green.shade50.withOpacity(0.5),
      onTap: _showNativeAlarmAssistantDialog,
    ));

    // 4. 我的請假申請與記錄
    menus.add(_buildMenuTile(
      icon: Icons.assignment_ind,
      title: '我的請假申請與記錄',
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyLeavePage())),
    ));

    // 5. 申請取消已批假期
    menus.add(_buildMenuTile(
      icon: Icons.cancel_presentation,
      title: '申請取消已批假期 (未來日子)',
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CancelLeaveRequestPage())),
    ));

    // 6. 桌面小工具
    menus.add(_buildMenuTile(
      icon: Icons.widgets,
      title: '桌面小工具與自動鬧鐘設定',
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DesktopWidgetsPage())),
    ));

    // 管理員專用控制台
    if (_isSuperAdmin || _isSR) {
      menus.add(const Padding(
        padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
        child: Text('管理員專用控制台', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
      ));

      menus.add(_buildMenuTile(
        icon: Icons.gavel,
        title: _isSuperAdmin ? '審批全廠請假申請' : '審批本隊 ($_userGroup 隊) 請假申請',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ApprovalPage(teamCode: _isSuperAdmin ? null : _userGroup))),
        iconColor: Colors.orange.shade800,
        textColor: Colors.orange.shade900,
        backgroundColor: const Color(0xFFFFF8E1),
      ));

      menus.add(_buildMenuTile(
        icon: Icons.settings,
        title: 'Google Sheets 行列配置',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GoogleSheetsConfigPage())),
      ));

      menus.add(_buildMenuTile(
        icon: Icons.holiday_village,
        title: '公眾假期與自訂休假管理',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HolidaysPage())),
      ));
    }

    return ListView(children: menus);
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
    Color? backgroundColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.transparent,
        border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? const Color(0xFF3F51B5)),
        title: Text(
          title,
          style: TextStyle(
            color: textColor ?? Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.black26, size: 20),
        onTap: onTap,
      ),
    );
  }
}