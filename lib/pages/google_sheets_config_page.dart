// lib/pages/google_sheets_config_page.dart
import 'package:flutter/material.dart';
import '../services/google_sheets_service.dart';

class GoogleSheetsConfigPage extends StatefulWidget {
  const GoogleSheetsConfigPage({super.key});

  @override
  State<GoogleSheetsConfigPage> createState() => _GoogleSheetsConfigPageState();
}

class _GoogleSheetsConfigPageState extends State<GoogleSheetsConfigPage> {
  bool _loading = true;
  Map<String, Map<String, dynamic>> _configStatus = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    for (var c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    if (mounted) setState(() => _loading = true);
    final status = await GoogleSheetsService.getSheetsConfigStatus();
    if (mounted) {
      setState(() {
        _configStatus = status;
        _loading = false;
      });
      // 建立 controllers
      for (var team in ['A', 'B', 'C', 'D']) {
        if (!_controllers.containsKey(team)) {
          final customUrl = status[team]?['customUrl'] ?? '';
          _controllers[team] = TextEditingController(text: customUrl);
        }
      }
    }
  }

  Future<void> _saveTeamUrl(String team) async {
    final url = _controllers[team]?.text.trim() ?? '';
    await GoogleSheetsService.saveCustomUrl(team, url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ $team 隊 URL 已保存'), backgroundColor: Colors.green),
      );
      await _loadConfig(); // 刷新顯示
    }
  }

  Future<void> _testTeamConnection(String team) async {
    final result = await GoogleSheetsService.testConnection(team);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$team 組: ${result['success'] == true ? '✅ 連接成功' : '❌ 連接失敗: ${result['message']}'}'),
        backgroundColor: result['success'] == true ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _resetToDefault(String team) async {
    _controllers[team]?.text = '';
    await GoogleSheetsService.saveCustomUrl(team, '');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🔄 $team 隊已重設為預設 URL'), backgroundColor: Colors.orange),
      );
      await _loadConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Sheets 備份設定'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '你可以為每個隊伍自訂 Apps Script 網址，留空則使用預設網址。\n修改後請按「保存」並測試連接。',
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...['A', 'B', 'C', 'D'].map((team) {
              final status = _configStatus[team] ?? {};
              final defaultUrl = status['defaultUrl'] ?? '';
              final isUsingCustom = (status['customUrl']?.isNotEmpty ?? false);
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('$team 隊', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          if (isUsingCustom)
                            Chip(
                              label: const Text('使用自訂'),
                              backgroundColor: Colors.amber.shade100,
                              avatar: const Icon(Icons.edit, size: 16),
                            )
                          else
                            Chip(
                              label: const Text('使用預設'),
                              backgroundColor: Colors.grey.shade200,
                              avatar: const Icon(Icons.cloud, size: 16),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.sync, color: Colors.blue),
                            onPressed: () => _testTeamConnection(team),
                            tooltip: '測試連接',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _controllers[team],
                        decoration: InputDecoration(
                          labelText: 'Apps Script URL',
                          hintText: defaultUrl,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _controllers[team]?.clear(),
                          ),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _saveTeamUrl(team),
                              icon: const Icon(Icons.save),
                              label: const Text('保存'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => _resetToDefault(team),
                            icon: const Icon(Icons.restore),
                            label: const Text('重設預設'),
                          ),
                        ],
                      ),
                      if (defaultUrl.isNotEmpty && !isUsingCustom)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '預設: $defaultUrl',
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                for (var team in ['A', 'B', 'C', 'D']) {
                  await _testTeamConnection(team);
                  await Future.delayed(const Duration(milliseconds: 300));
                }
              },
              icon: const Icon(Icons.network_check),
              label: const Text('測試所有隊伍連接'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}