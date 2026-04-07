import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shift_app/utils/auth_util.dart';

class AnnouncementPage extends StatefulWidget {
  final String team;
  final bool canEdit;

  const AnnouncementPage({super.key, required this.team, required this.canEdit});

  @override
  State<AnnouncementPage> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  late String _selectedTeam;
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _permissionCode;

  @override
  void initState() {
    super.initState();
    _selectedTeam = widget.team;
    _loadPermission();
    _fetchAnnouncement();
  }

  Future<void> _loadPermission() async {
    final code = await AuthUtil.getPermissionCode();
    setState(() {
      _permissionCode = code;
    });
  }

  Future<void> _fetchAnnouncement() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('team_announcements')
          .doc(_selectedTeam)
          .get();
      if (doc.exists) {
        _controller.text = doc['content'] ?? '';
      }
    } catch (e) {
      debugPrint("讀取失敗: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAnnouncement() async {
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('team_announcements')
          .doc(_selectedTeam)
          .set({
        'content': _controller.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 公告已儲存'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 儲存失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSuperAdmin = _permissionCode == 'SM';
    final bool canSelectTeam = widget.canEdit && isSuperAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(canSelectTeam ? '編輯隊伍公告' : '${widget.team} 隊公告'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (widget.canEdit && !_isLoading)
            IconButton(
              onPressed: _isSaving ? null : _saveAnnouncement,
              icon: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (canSelectTeam)
              DropdownButtonFormField<String>(
                value: _selectedTeam,
                items: const ['A', 'B', 'C', 'D'].map((team) => DropdownMenuItem(value: team, child: Text('$team 隊'))).toList(),
                onChanged: (team) {
                  if (team != null) {
                    setState(() {
                      _selectedTeam = team;
                      _isLoading = true;
                    });
                    _fetchAnnouncement();
                  }
                },
                decoration: const InputDecoration(labelText: '選擇隊伍', border: OutlineInputBorder()),
              ),
            if (canSelectTeam) const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: widget.canEdit,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(color: Colors.black), // 強制黑色文字
                decoration: InputDecoration(
                  hintText: widget.canEdit ? '請輸入公告內容...' : '暫無公告',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: widget.canEdit ? Colors.white : Colors.grey.shade100,
                  hintStyle: const TextStyle(color: Colors.grey),
                ),
              ),
            ),
            if (widget.canEdit)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('編輯後請點右上角 ✓ 儲存', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}