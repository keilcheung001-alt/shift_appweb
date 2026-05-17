import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/constants/constants.dart';
import 'package:shift_app/pages/desktop_widgets_page.dart';

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

  // 🔒 新增防窺狀態控制（純前台畫面防窺，不影響底層真實數據）
  bool _obscureName = true;
  bool _obscureStaffId = true;

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
    final rawName = nameController.text.trim();
    final nickName = nickNameController.text.trim();
    final rawStaffId = staffIdController.text.trim();
    final jobTitle = jobTitleController.text.trim();

    if (rawName.isEmpty || rawStaffId.isEmpty) {
      _showMessage('請輸入姓名和員工編號');
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // 🎯 撥亂反正：儲存進系統的 100% 是真實、無修改的原始數據！後面所有檔案皆可正常讀取與對對碰
    await prefs.setString(SPK_MY_NAME, rawName);
    await prefs.setString(SPK_NICKNAME, nickName.isEmpty ? rawName : nickName);
    await prefs.setString(SPK_STAFF_ID, rawStaffId);
    await prefs.setString(SPK_JOB_TITLE, jobTitle);
    await prefs.setString(SPK_GROUP, homeGroup);
    await prefs.setString(SPK_LOGIN_GROUP, selectedGroup);
    await prefs.setString(SPK_PERMISSION_CODE, role == '隊長' ? 'ADMIN' : 'MEMBER');
    await prefs.setInt(SPK_LOGIN_TIMESTAMP, DateTime.now().millisecondsSinceEpoch);

    _showMessage('✅ 登入成功！(數據已安全同步，後台完全可見)');

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    // 跳轉至小工具頁面
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const DesktopWidgetsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('登入 (前台防窺版)'),
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
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                ),
                child: Column(
                  children: [
                    Card(
                      color: Colors.white.withOpacity(0.95),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('👤 個人資訊 (畫面已啟用防窺保護)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),

                            // 🔒 姓名輸入框：加入小眼睛開關，避免翻出來直接看到名
                            TextField(
                              controller: nameController,
                              obscureText: _obscureName, // 畫面隱蔽控制
                              decoration: InputDecoration(
                                labelText: '姓名 *',
                                hintText: '例如：張三豐',
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureName ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                                  onPressed: () {
                                    setState(() => _obscureName = !_obscureName);
                                  },
                                ),
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

                            // 🔒 員工編號輸入框：密碼化隱蔽，輸入完自動變圓點
                            TextField(
                              controller: staffIdController,
                              obscureText: _obscureStaffId, // 畫面隱蔽控制
                              decoration: InputDecoration(
                                labelText: '員工編號 *',
                                hintText: '例如：B001',
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureStaffId ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                                  onPressed: () {
                                    setState(() => _obscureStaffId = !_obscureStaffId);
                                  },
                                ),
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

                    Card(
                      color: Colors.white.withOpacity(0.95),
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
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

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