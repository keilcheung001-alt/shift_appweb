// lib/pages/whatsapp_config_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WhatsAppConfigPage extends StatefulWidget {
  const WhatsAppConfigPage({super.key});

  @override
  State<WhatsAppConfigPage> createState() => _WhatsAppConfigPageState();
}

class _WhatsAppConfigPageState extends State<WhatsAppConfigPage> {
  final Map<String, TextEditingController> ctrls = {
    'A': TextEditingController(),
    'B': TextEditingController(),
    'C': TextEditingController(),
    'D': TextEditingController(),
  };

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool loading = true;

  List<String> get teams => ['A', 'B', 'C', 'D'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final team in teams) {
      ctrls[team]!.text = prefs.getString('whatsapplink$team') ?? '';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      // 有紅色 error 時唔儲存
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先修正紅色欄位，再儲存')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    for (final team in teams) {
      final link = ctrls[team]!.text.trim();
      if (link.isNotEmpty) {
        await prefs.setString('whatsapplink$team', link);
      } else {
        await prefs.remove('whatsapplink$team');
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 已儲存 WhatsApp 連結')),
    );
  }

  String? _validateLink(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null; // 允許留空
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      return '請輸入有效網址（必須以 http:// 或 https:// 開頭）';
    }
    // 可以之後再加更多 regex 驗證
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📱 WhatsApp 群組設定'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '為每個隊伍儲存對應 WhatsApp 群組邀請連結。\n'
                  '留空代表該隊伍暫時未設定群組。',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            for (final team in teams) ...[
              TextFormField(
                controller: ctrls[team],
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: '$team 隊邀請連結',
                  hintText: 'https://chat.whatsapp.com/....',
                  border: const OutlineInputBorder(),
                ),
                validator: _validateLink,
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  '儲存',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
