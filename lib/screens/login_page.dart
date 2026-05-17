import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/constants/constants.dart';
import 'package:shift_app/pages/team_menu_page.dart';

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

  String homeGroup = 'A';
  String selectedGroup = 'A';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      nameController.text = prefs.getString(SPK_MY_NAME) ?? '';
      nickNameController.text = prefs.getString(SPK_NICKNAME) ?? '';
      staffIdController.text = prefs.getString(SPK_STAFF_ID) ?? '';
      jobTitleController.text = prefs.getString(SPK_JOB_TITLE) ?? '';
      homeGroup = prefs.getString(SPK_GROUP) ?? 'A';
      selectedGroup = prefs.getString(SPK_LOGIN_GROUP) ?? homeGroup;
      loading = false;
    });
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _handleLogin(String role) async {
    final name = nameController.text.trim();
    final nickName = nickNameController.text.trim();
    final staffId = staffIdController.text.trim();
    final jobTitle = jobTitleController.text.trim();

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
    await prefs.setString(SPK_PERMISSION_CODE, role == '隊長' ? 'ADMIN' : 'MEMBER');
    await prefs.setInt(SPK_LOGIN_TIMESTAMP, DateTime.now().millisecondsSinceEpoch);

    // 兩個角色都俾管理員權限
    const canFullEdit = true;
    const isSuperAdmin = true;

    _showMessage('✅ 登入成功 ($role)');

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TeamMenuPage(
          staffId: staffId,
          group: selectedGroup,
          canFullEdit: canFullEdit,
          isSuperAdmin: isSuperAdmin,
          role: role,
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
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.blue.shade700, Colors.indigo.shade700]),
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
                ),
                child: Column(
                  children: [
                    // 個人資訊卡（保持你原來的樣式，冇改過）
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

                    // 隊伍設定卡（保持你原來的樣式，只係刪除咗 workAlarmEnabled checkbox）
                    Card(
                      color: Colors.white.withValues(alpha: 0.95),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('👥 隊伍設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: homeGroup,
                              decoration: const InputDecoration(
                                labelText: '所屬隊伍 *',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: const ['A', 'B', 'C', 'D']
                                  .map((team) => DropdownMenuItem(value: team, child: Text('$team 隊')))
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    homeGroup = value;
                                    if (selectedGroup.isEmpty) selectedGroup = value;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: selectedGroup,
                              decoration: const InputDecoration(
                                labelText: '預設檢查隊伍',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: const ['A', 'B', 'C', 'D']
                                  .map((team) => DropdownMenuItem(value: team, child: Text('$team 隊')))
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    selectedGroup = value;
                                  });
                                }
                              },
                            ),
                            // 🔥 刪除咗「啟用工作警報」checkbox，因為佢冇用途
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 🔥 底部兩個按鈕：上下排列，唔好太低
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _handleLogin('隊長'),
                            icon: const Icon(Icons.shield, color: Colors.white),
                            label: const Text('隊長登入', style: TextStyle(fontSize: 16)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _handleLogin('隊員'),
                            icon: const Icon(Icons.people, color: Colors.white),
                            label: const Text('隊員登入', style: TextStyle(fontSize: 16)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
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