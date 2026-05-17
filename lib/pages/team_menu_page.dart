import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/shift_calculator.dart';
import '../constants/constants.dart';
import 'my_leave_page.dart';
import 'announcement_page.dart';
import 'desktop_widgets_page.dart';
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
  late Timer _timer;
  String _todayShift = '...';

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
    _initData();
    _startTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    await Future.delayed(const Duration(milliseconds: 300));
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

  void _updateShiftInfo() {
    final now = DateTime.now();
    final group = widget.group ?? 'A';
    try {
      _todayShift = ShiftCalculator.calculateShift(group, now);
    } catch (e) {
      _todayShift = '常班';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRole = widget.role ?? '員工';
    final userGroup = widget.group ?? 'A';

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        title: const Text('隊伍管理選單', style: TextStyle(fontWeight: FontWeight.normal, fontSize: 20)),
        backgroundColor: const Color(0xFF4A55A2),
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
                // 1. 👤 頂部用戶個人資料卡片
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3F51B5),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: Text(
                          userGroup,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'cheungyiukei',
                              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '工號: ${widget.staffId ?? "583472"} (暱稱: 基)',
                              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)
                            ),
                            Text(
                              '權限: $userRole | 所屬組別: $userGroup 隊',
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. 📢 黃色公告欄
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
                            String announcementText = '一則 testing';
                            if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                              final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                              announcementText = data['content'] ?? '一則 testing';
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('一則', style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
                                Text(announcementText, style: const TextStyle(color: Colors.black54, fontSize: 13)),
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

                // 3. 🔲 四色隊伍日曆快速切換按鈕
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '隊伍日曆 (快速切換)    [今日: $_todayShift班]',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
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
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            height: 55,
                            decoration: BoxDecoration(
                              color: _getTeamButtonColor(t),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? Colors.black87 : Colors.transparent,
                                width: isSelected ? 3 : 0,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                t,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
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

                const SizedBox(height: 16),

                // 4. 🎛️ 底部功能列表（全體直接平鋪顯示）
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text('功能選單', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                      ),
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
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AnnouncementPage(team: userGroup, canEdit: true),
                            ),
                          );
                        },
                      ),
                      _buildMenuTile(
                        icon: Icons.grid_view,
                        title: '桌面小工具與鬧鐘',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DesktopWidgetsPage())),
                      ),

                      Padding(
                        padding: const EdgeInsets.only(left: 16, top: 20, bottom: 8),
                        child: const Text(
                          '管理功能',
                          style: TextStyle(color: Colors.indigo, fontSize: 15, fontWeight: FontWeight.bold)
                        ),
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

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Icon(icon, color: const Color(0xFF3F51B5), size: 24),
        title: Text(title, style: const TextStyle(color: Colors.black87, fontSize: 16)),
        trailing: const Icon(Icons.chevron_right, color: Colors.black26, size: 20),
        onTap: onTap,
      ),
    );
  }
}