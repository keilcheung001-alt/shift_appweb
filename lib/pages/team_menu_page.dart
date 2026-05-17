import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/shift_calculator.dart';
import '../constants/constants.dart';
import 'my_leave_page.dart';
import 'announcement_page.dart';
import '../screens/login_page.dart';

// 🔌 引入你底層真實的 4 個隊伍日曆檔案
import 'full_calendar_a.dart';
import 'full_calendar_b.dart';
import 'full_calendar_c.dart';
import 'full_calendar_d.dart';

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

  // 🔍 控制大月曆雙指放大與還原
  final TransformationController _transformationController = TransformationController();

  // 🕒 廠房實時時間變數
  late Timer _timer;
  String _todayShift = '加載中…';

  // 🎨 ABCD 四個隊伍按鈕的原裝代表色（100% 還原你原本的顏色）
  Color _getTeamColor(String team) {
    switch (team) {
      case 'A': return const Color(0xFF3F51B5); // 靛藍色
      case 'B': return const Color(0xFFFF8F00); // 橙色
      case 'C': return const Color(0xFF4CAF50); // 綠色
      case 'D': return const Color(0xFFE91E63); // 粉紅色
      default: return Colors.indigo;
    }
  }

  @override
  void initState() {
    super.initState();
    _initData();
    _startTimer(); // 啟動實時更新，免除計時器崩潰
  }

  @override
  void dispose() {
    _timer.cancel(); // 銷毀定時器，防止記憶體洩漏
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() {
        _currentTeam = widget.group ?? 'A';
        _isLoading = false;
        _updateShiftInfo();
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_isLoading) {
        setState(() {
          _updateShiftInfo();
        });
      }
    });
  }

  // 🕒 完美對接你底層真實的 ShiftCalculator.calculateShift(String teamCode, DateTime date)
  void _updateShiftInfo() {
    final now = DateTime.now();
    final group = widget.group ?? 'A';

    try {
      // ✅ 修正：嚴格遵循 (String, DateTime) 位置參數，不帶任何命名引數
      _todayShift = ShiftCalculator.calculateShift(group, now);
    } catch (e) {
      _todayShift = '常班';
    }
  }

  // 📦 完美調用四個隊伍的日曆畫面（補齊 required 參數）
  Widget _buildCalendarView(String team) {
    final sId = widget.staffId ?? '0000';
    final edit = widget.canFullEdit ?? false;
    final admin = widget.isSuperAdmin ?? false;

    switch (team) {
      case 'A': return FullCalendarATeam(staffId: sId, canFullEdit: edit, isSuperAdmin: admin);
      case 'B': return FullCalendarBTeam(staffId: sId, canFullEdit: edit, isSuperAdmin: admin);
      case 'C': return FullCalendarCTeam(staffId: sId, canFullEdit: edit, isSuperAdmin: admin);
      case 'D': return FullCalendarDTeam(staffId: sId, canFullEdit: edit, isSuperAdmin: admin);
      default: return const Center(child: Text('未知隊伍'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRole = widget.role ?? '員工';
    final userGroup = widget.group ?? 'A';
    final isManagement = (widget.canFullEdit == true || widget.isSuperAdmin == true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('團隊主要選單'),
        backgroundColor: _getTeamColor(_currentTeam),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacementNamed(context, ROUTE_LOGIN);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. 頂部用戶個人資料卡片
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: _getTeamColor(_currentTeam).withOpacity(0.1),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: _getTeamColor(_currentTeam),
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('工號: ${widget.staffId ?? "未登入"}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('權限: $userRole | 所屬組別: $userGroup 隊'),
                          ],
                        ),
                      ),
                      // 今日班次
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getTeamColor(_currentTeam),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '今日: $_todayShift班',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 2. ABCD 四個切換隊伍按鈕
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['A', 'B', 'C', 'D'].map((t) {
                      final isSelected = _currentTeam == t;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _currentTeam = t;
                            });
                            _transformationController.value = Matrix4.identity(); // 切換隊伍時重置縮放
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? _getTeamColor(t) : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? Colors.black26 : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$t 隊',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 12),

                // 3. 大月曆顯示區域 (支援雙指放大縮小)
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: () {
                      _transformationController.value = Matrix4.identity(); // 雙擊還原大小
                    },
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 1.0,
                      maxScale: 4.0,
                      boundaryMargin: const EdgeInsets.all(20.0),
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEEEEEE)),
                        ),
                        child: _buildCalendarView(_currentTeam),
                      ),
                    ),
                  ),
                ),

                // 4. 底部功能選單
                if (!isManagement) ...[
                  // 👤 一般普通員工按鈕
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('申請請假'),
                            onPressed: () {
                              // ✅ 修正：對接你真實的 const MyLeavePage({super.key})，不傳 staffId
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const MyLeavePage()),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.announcement),
                            label: const Text('查看公告'),
                            onPressed: () {
                              // ✅ 修正：精確傳入 AnnouncementPage 需要的 required 參數
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AnnouncementPage(
                                    team: userGroup,
                                    canEdit: isManagement,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // 👑 管理層清單選單（100% 還原你原本的清單）
                  Expanded(
                    child: ListView(
                      children: [
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.gavel,
                          title: '請假批核管理',
                          onTap: () => Navigator.pushNamed(context, ROUTE_APPROVAL),
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.calendar_today,
                          title: '假期與自訂節日管理',
                          onTap: () => Navigator.pushNamed(context, ROUTE_HOLIDAYS),
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.settings,
                          title: 'Google Sheets 配置',
                          onTap: () => Navigator.pushNamed(context, ROUTE_GOOGLE_SHEETS_CONFIG),
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.chat_bubble_outline,
                          title: 'WhatsApp 通知配置',
                          onTap: () => Navigator.pushNamed(context, ROUTE_WHATSAPP_CONFIG),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  // UI 封裝組件
  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: const Color(0xFF1A237E), size: 24),
      title: Text(title, style: const TextStyle(color: Colors.black87, fontSize: 16)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}