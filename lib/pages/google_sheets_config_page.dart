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
  Map<String, dynamic> _configStatus = {};

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    if (mounted) setState(() => _loading = true);
    _configStatus = await GoogleSheetsService.getSheetsConfigStatus();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _testAllConnections() async {
    for (final team in ['A', 'B', 'C', 'D']) {
      final result = await GoogleSheetsService.testConnection(team);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$team組: ${result['success'] == true ? '連接成功' : '連接失敗'}'),
          backgroundColor: result['success'] == true ? Colors.green : Colors.red,
        ),
      );
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
                        '已固定使用四隊 Apps Script URL，無需手動設定。',
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📊 連接狀態',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['A', 'B', 'C', 'D'].map((team) {
                        final teamStatus = (_configStatus[team] as Map?)?.cast<String, dynamic>() ?? {};
                        final isConfigured = teamStatus['configured'] == true;
                        return Chip(
                          label: Text('$team組'),
                          backgroundColor: isConfigured ? Colors.green.shade100 : Colors.red.shade100,
                          avatar: Icon(
                            isConfigured ? Icons.check : Icons.close,
                            size: 16,
                            color: isConfigured ? Colors.green : Colors.red,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _testAllConnections,
                icon: const Icon(Icons.sync),
                label: const Text('測試所有連接'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}