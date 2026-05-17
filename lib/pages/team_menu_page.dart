import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/shift_calculator.dart';
import '../constants/constants.dart';
import 'my_leave_page.dart';
import 'announcement_page.dart';
import 'settings_page.dart';
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

  Color _getTeamColor(String team) {
    switch (team) {
      case 'A': return const Color(0xFF3F51B5);
      case 'B': return const Color(0xFFFF8F00);
      case 'C': return const Color(0xFF4CAF50);
      case 'D': return const Color(0xFFE91E63);
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
                // 1. 👤 頂部用戶卡片
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

                // 2. 📢 最新通告公告看板（緊接在用戶卡片下方）
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.campaign, color: Colors.amber.shade900, size: 22),
                          const SizedBox(width: 6),
                          Text(
                            '最新通告公告',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 12, color: Colors.amber),
                      Container(
                        height: 65,
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('announcements')
                              .where('targetTeam', isEqualTo: _currentTeam)
                              .orderBy('timestamp', descending: true)
                              .limit(1)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                              return const Center(
                                child: Text('目前沒有新通告', style: TextStyle(color: Colors.black54, fontSize: 13))
                              );
                            }
                            final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                            final content = data['content'] ?? '';
                            final ts = data['timestamp'] as Timestamp?;
                            final dateStr = ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate()) : '';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('📌 內容: $content', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                                const SizedBox(height: 2),
                                Text('⏰ 時間: $dateStr', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. 🔲 ABCD 隊伍切換按鈕（在公告看板下方）
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
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
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

                const SizedBox(height: 10),

                // 4. 🎛️ 底部功能清單（嚴格遵循 7 個特定項目排版）
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
                        icon: Icons.calendar_month_outlined,
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
                      const Divider(height: 1),
                      _buildMenuTile(
                        icon: Icons.tune,
                        title: '設定',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SettingsPage()),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      _buildMenuTile(
                        icon: Icons.announcement,
                        title: '公告管理',
                        onTap: () {
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
                      const Divider(height: 1),
                      _buildMenuTile(
                        icon: Icons.history,
                        title: '我的請假紀錄',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const MyLeavePage()),
                          );
                        },
                      ),
                      const Divider(height: 1),
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: const Color(0xFF1A237E), size: 24),
      title: Text(title, style: const TextStyle(color: Colors.black87, fontSize: 16)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}