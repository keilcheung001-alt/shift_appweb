// lib/screens/login_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/constants/constants.dart';
import 'package:shift_app/pages/team_menu_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController nickNameController = TextEditingController();
  final TextEditingController staffIdController = TextEditingController();
  final TextEditingController jobTitleController = TextEditingController();
  final TextEditingController permissionCodeController = TextEditingController();

  String homeGroup = 'A';
  String selectedGroup = 'A';
  bool workAlarmEnabled = false;
  bool loading = true;
  bool isVerifying = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    nameController.dispose();
    nickNameController.dispose();
    staffIdController.dispose();
    jobTitleController.dispose();
    permissionCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        nameController.text = prefs.getString(SPK_MY_NAME) ?? '';
        nickNameController.text = prefs.getString(SPK_NICKNAME) ?? '';
        staffIdController.text = prefs.getString(SPK_STAFF_ID) ?? '';
        jobTitleController.text = prefs.getString(SPK_JOB_TITLE) ?? '';
        homeGroup = prefs.getString(SPK_GROUP) ?? 'A';
        selectedGroup = prefs.getString(SPK_LOGIN_GROUP) ?? homeGroup;
        workAlarmEnabled = prefs.getBool(SPK_WORK_ALARM_ENABLED) ?? false;
        loading = false;
      });
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _handleLogin({String? presetPermissionCode}) async {
    final name = nameController.text.trim();
    final nickName = nickNameController.text.trim();
    final staffId = staffIdController.text.trim();
    final jobTitle = jobTitleController.text.trim();

    // 如果傳入 presetPermissionCode，就用佢；否則用輸入框嘅值
    final permissionCode = (presetPermissionCode ?? permissionCodeController.text.trim()).toUpperCase();

    if (name.isEmpty || staffId.isEmpty) {
      _showMessage('請輸入姓名和員工編號');
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(SPK_MY_NAME, name);
    await prefs.setString(SPK_NICKNAME, nickName);
    await prefs.setString(SPK_STAFF_ID, staffId);
    await prefs.setString(SPK_JOB_TITLE, jobTitle);
    await prefs.setString(SPK_GROUP, homeGroup);
    await prefs.setString(SPK_LOGIN_GROUP, selectedGroup);
    await prefs.setString(SPK_PERMISSION_CODE, permissionCode);
    await prefs.setBool(SPK_WORK_ALARM_ENABLED, workAlarmEnabled);

    bool canFullEdit = false;
    bool isSuperAdmin = false;

    if (permissionCode == PERMISSION_CODE_SUPER_ADMIN) {
      canFullEdit = true;
      isSuperAdmin = true;
    } else if (permissionCode == PERMISSION_CODE_TEAM_LEAD) {
      canFullEdit = true;
      selectedGroup = homeGroup;
    } else {
      selectedGroup = homeGroup;
      canFullEdit = false;
    }

    if (mounted) setState(() => isVerifying = true);

    await prefs.setInt(SPK_LOGIN_TIMESTAMP, DateTime.now().millisecondsSinceEpoch);

    if (isSuperAdmin) {
      _showMessage('✅ 登入成功 (SM - 隊長)');
    } else if (canFullEdit) {
      _showMessage('✅ 登入成功 ($selectedGroup 管理員)');
    } else {
      _showMessage('✅ 登入成功 ($selectedGroup 員工)');
    }

    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TeamMenuPage(
          staffId: staffId,
          group: selectedGroup,
          canFullEdit: canFullEdit,
          isSuperAdmin: isSuperAdmin,
        ),
      ),
    );

    if (mounted) setState(() => isVerifying = false);
  }

  // 可點擊的權限卡片 - 直接調用 _handleLogin 並傳入權限碼
  Widget _buildClickablePermissionHint(String label, String desc, IconData icon, Color bgColor, String permissionCode) {
    return GestureDetector(
      onTap: () {
        _handleLogin(presetPermissionCode: permissionCode);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: bgColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: bgColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                desc,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('登入'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade700, Colors.indigo.shade700],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 個人資訊卡
                    Card(
                      color: Colors.white.withValues(alpha: 0.95),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('👤 個人資訊', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            TextField(
                              controller: nameController,
                              decoration: const InputDecoration(
                                labelText: '姓名 *',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: nickNameController,
                              decoration: const InputDecoration(
                                labelText: '暱稱（可選）',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: staffIdController,
                              decoration: const InputDecoration(
                                labelText: '員工編號 *',
                                hintText: 'B001',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: jobTitleController,
                              decoration: const InputDecoration(
                                labelText: '職位（如: UR, SM, 可選）',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 隊伍 & 權限卡 - 改用 DropdownButtonFormField（網頁版穩定）
                    Card(
                      color: Colors.white.withValues(alpha: 0.95),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('👥 隊伍 & 權限', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),

                            // 所屬隊伍
                            DropdownButtonFormField<String>(
                              value: homeGroup,
                              decoration: const InputDecoration(
                                labelText: '所屬隊伍 *',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: const ['A', 'B', 'C', 'D']
                                  .map((team) => DropdownMenuItem(
                                value: team,
                                child: Text('$team 隊'),
                              ))
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    homeGroup = value;
                                    // 如果預設隊伍為空，同步更新
                                    if (selectedGroup.isEmpty) selectedGroup = value;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 12),

                            // 預設檢查隊伍
                            DropdownButtonFormField<String>(
                              value: selectedGroup,
                              decoration: const InputDecoration(
                                labelText: '預設檢查隊伍（SR 固定用所屬隊伍）',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: const ['A', 'B', 'C', 'D']
                                  .map((team) => DropdownMenuItem(
                                value: team,
                                child: Text('$team 隊'),
                              ))
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    selectedGroup = value;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 12),

                            CheckboxListTile(
                              value: workAlarmEnabled,
                              onChanged: (v) {
                                setState(() => workAlarmEnabled = v ?? false);
                              },
                              title: const Text('啟用工作警報'),
                              contentPadding: EdgeInsets.zero,
                              activeColor: Colors.indigo,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 三張可點擊的權限卡片
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🔐 選擇權限登入',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          _buildClickablePermissionHint('隊長', 'SM', Icons.shield, Colors.green, PERMISSION_CODE_SUPER_ADMIN),
                          _buildClickablePermissionHint('管理員', 'SR', Icons.person, Colors.orange, PERMISSION_CODE_TEAM_LEAD),
                          _buildClickablePermissionHint('普通員工', '（留空）', Icons.people, Colors.blue, ''),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}