// lib/pages/approval_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../constants/constants.dart';
import '../models/models.dart';
import '../utils/auth_util.dart';
import '../services/whatsapp_groups.dart';
import '../utils/widget_snapshot_writer.dart';

class PendingLeaveItem {
  final String docId;
  final String dateKey;
  final String team;
  final String name;
  final String nickname; // [ADDED]
  final String reason;
  final int days;
  final String status;
  final int index;

  PendingLeaveItem({
    required this.docId,
    required this.dateKey,
    required this.team,
    required this.name,
    required this.nickname, // [ADDED]
    required this.reason,
    required this.days,
    required this.status,
    required this.index,
  });
}

class ApprovalPage extends StatefulWidget {
  final String? teamCode;
  const ApprovalPage({super.key, this.teamCode});

  @override
  State<ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<ApprovalPage> {
  bool _canApprove = false;
  bool _loading = true;
  bool _isSuperAdmin = false;
  bool _isTeamLead = false;
  bool _isBatchProcessing = false;
  String _selectedTeam = 'A';
  String _homeGroup = '';
  List<PendingLeaveItem> _pendingItems = [];
  Set<String> _selectedItemIds = {};

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    _isSuperAdmin = await AuthUtil.getIsSuperAdmin();
    _isTeamLead = await AuthUtil.getIsTeamLead();
    _homeGroup = await AuthUtil.getHomeGroup();
    _canApprove = _isSuperAdmin || _isTeamLead;

    if (!_canApprove) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 您沒有核准權限')),
        );
        Navigator.of(context).pop();
      }
      return;
    }

    if (_isSuperAdmin) {
      if (widget.teamCode != null) _selectedTeam = widget.teamCode!;
    } else {
      _selectedTeam = _homeGroup;
    }

    if (mounted) setState(() => _loading = false);
    _loadPendingItems();
  }

  String _getCollectionName(String team) {
    return FIRESTORE_LEAVE_COLLECTIONS[team.toUpperCase()] ?? FIRESTORE_A_TEAM_LEAVE;
  }

  Future<void> _loadPendingItems() async {
    try {
      final collectionName = _getCollectionName(_selectedTeam);
      final snapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .get(const GetOptions(source: Source.server));

      final items = <PendingLeaveItem>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final dateKey = data['dateKey'] as String? ?? doc.id;
        final names = (data['names'] as List<dynamic>?)?.cast<String>() ?? [];
        final nicknames = (data['nicknames'] as List<dynamic>?)?.cast<String>() ?? []; // [ADDED]
        final reasons = (data['reasons'] as List<dynamic>?)?.cast<String>() ?? [];
        List<String> statuses = (data['statuses'] as List<dynamic>?)?.cast<String>() ?? [];

        if (statuses.length != names.length) {
          statuses = List.filled(names.length, 'pending');
        }

        for (int i = 0; i < names.length; i++) {
          final status = (i < statuses.length) ? statuses[i] : 'pending';
          if (status == 'pending') {
            items.add(PendingLeaveItem(
              docId: doc.id,
              dateKey: dateKey,
              team: _selectedTeam,
              name: names[i],
              nickname: i < nicknames.length ? nicknames[i] : '', // [ADDED]
              reason: i < reasons.length ? reasons[i] : '',
              days: 1,
              status: status,
              index: i,
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
          _pendingItems = items;
          _selectedItemIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 載入失敗: $e')),
        );
      }
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedItemIds.contains(id)) {
        _selectedItemIds.remove(id);
      } else {
        _selectedItemIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedItemIds.length == _pendingItems.length) {
        _selectedItemIds.clear();
      } else {
        _selectedItemIds.clear();
        for (var item in _pendingItems) {
          _selectedItemIds.add('${item.docId}_${item.index}');
        }
      }
    });
  }

  Future<void> _batchApprove() async {
    if (_selectedItemIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇要批准的項目')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量批准'),
        content: Text('確定批准所選的 ${_selectedItemIds.length} 項請假？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('批准', style: TextStyle(color: Colors.green))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isBatchProcessing = true);

    final idsToProcess = List<String>.from(_selectedItemIds);
    final itemsToNotify = <PendingLeaveItem>[];

    try {
      for (final id in idsToProcess) {
        final parts = id.split('_');
        if (parts.length != 2) continue;
        final docId = parts[0];
        final index = int.parse(parts[1]);
        final item = _pendingItems.firstWhere(
          (i) => i.docId == docId && i.index == index,
          orElse: () => throw Exception('找不到項目'),
        );
        itemsToNotify.add(item);
        await _updateSingleItemStatus(item, 'approved', skipReload: true);
      }

      await _sendBatchWhatsAppWithItems(itemsToNotify);
      await _loadPendingItems();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 批量批准失敗: $e')));
      }
    } finally {
      if (mounted) setState(() => _isBatchProcessing = false);
    }
  }

  Future<void> _sendBatchWhatsAppWithItems(List<PendingLeaveItem> items) async {
    if (items.isEmpty) return;
    final team = items.first.team;
    final groupLink = await WhatsAppGroups.getLinkForTeam(team);
    if (groupLink == null || groupLink.isEmpty) {
      _showErrorDialog('隊伍 $team 未設定群組連結');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final approverNickname = prefs.getString(SPK_NICKNAME) ?? '管理員';
    final itemsList = items.map((item) {
      final displayName = item.nickname.isNotEmpty ? '${item.nickname} (${item.name})' : item.name; // [ADDED]
      return '👤 $displayName - ${item.dateKey} (${item.reason.isNotEmpty ? item.reason : '無'})';
    }).join('\n');
    final message = '✅ 批量批准請假\n\n$itemsList\n\n🔍 審批人: $approverNickname';
    await Clipboard.setData(ClipboardData(text: message));
    _showInfoDialog('訊息已複製到剪貼簿，請手動貼上到 WhatsApp 群組');
    final launchUri = Uri.parse(groupLink);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    } else {
      _showErrorDialog('無法開啟連結，請手動複製訊息');
    }
  }

  Future<void> _updateSingleItemStatus(
    PendingLeaveItem item,
    String newStatus, {
    bool skipReload = false,
  }) async {
    if (mounted) {
      setState(() {
        _pendingItems.removeWhere((i) => i.docId == item.docId && i.name == item.name);
        _selectedItemIds.remove('${item.docId}_${item.index}');
      });
    }

    try {
      final docRef = FirebaseFirestore.instance.collection(_getCollectionName(item.team)).doc(item.docId);
      final doc = await docRef.get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final names = List<String>.from(data['names'] ?? []);
      final statuses = List<String>.from(data['statuses'] ?? List.filled(names.length, 'pending'));

      final normalizedName = item.name.replaceAll(RegExp(r'\s'), '');
      final idx = names.indexWhere((n) => n.replaceAll(RegExp(r'\s'), '') == normalizedName);
      if (idx != -1) {
        statuses[idx] = newStatus;
        final allDone = statuses.every((s) => s != 'pending');
        await docRef.update({
          'statuses': statuses,
          'status': allDone ? 'approved' : 'partial',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await WidgetSnapshotWriter.forceRefreshForTeam(item.team);
      if (!skipReload && mounted) await _loadPendingItems();
    } catch (e) {
      if (mounted) setState(() => _pendingItems.add(item));
    }
  }

  void _showInfoDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ℹ️ 提示'),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 提示'),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))],
      ),
    );
  }

  Future<void> _approveSingle(PendingLeaveItem item) async {
    await _updateSingleItemStatus(item, 'approved');
    _sendSingleWhatsApp(item);
  }

  Future<void> _rejectSingle(PendingLeaveItem item) async {
    await _updateSingleItemStatus(item, 'rejected');
  }

  Future<void> _sendSingleWhatsApp(PendingLeaveItem item) async {
    try {
      final groupLink = await WhatsAppGroups.getLinkForTeam(item.team);
      if (groupLink == null || groupLink.isEmpty) {
        _showErrorDialog('隊伍 ${item.team} 未設定群組連結');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final approverNickname = prefs.getString(SPK_NICKNAME) ?? '管理員';
      final displayName = item.nickname.isNotEmpty ? '${item.nickname} (${item.name})' : item.name; // [ADDED]
      final message = '✅ 已核准請假\n\n👤 員工: $displayName\n📅 日期: ${item.dateKey}\n📝 原因: ${item.reason.isNotEmpty ? item.reason : '無'}\n🔍 審批人: $approverNickname';
      await Clipboard.setData(ClipboardData(text: message));
      _showInfoDialog('訊息已複製到剪貼簿，請手動貼上到 WhatsApp 群組');
      final launchUri = Uri.parse(groupLink);
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('WhatsApp 發送失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('請假核准'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _selectedItemIds.length == _pendingItems.length && _pendingItems.isNotEmpty
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
            ),
            onPressed: _pendingItems.isEmpty ? null : _toggleSelectAll,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPendingItems),
        ],
      ),
      body: Column(
        children: [
          if (_isSuperAdmin)
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButton<String>(
                value: _selectedTeam,
                items: const ['A', 'B', 'C', 'D']
                    .map((team) => DropdownMenuItem(value: team, child: Text('$team 隊')))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedTeam = value;
                      _loadPendingItems();
                    });
                  }
                },
              ),
            ),
          if (_selectedItemIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Text('已選擇 ${_selectedItemIds.length} 項', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _isBatchProcessing ? null : _batchApprove,
                    icon: _isBatchProcessing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(_isBatchProcessing ? '處理中...' : '批量批准'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _pendingItems.isEmpty
                ? const Center(child: Text('暫無待核准請假'))
                : ListView.builder(
                    itemCount: _pendingItems.length,
                    itemBuilder: (context, index) {
                      final item = _pendingItems[index];
                      final itemId = '${item.docId}_${item.index}';
                      final displayName = item.nickname.isNotEmpty ? '${item.nickname} (${item.name})' : item.name; // [ADDED]

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: ListTile(
                          leading: Checkbox(
                            value: _selectedItemIds.contains(itemId),
                            onChanged: (_) => _toggleSelection(itemId),
                          ),
                          title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)), // [MODIFIED]
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('📅 日期: ${item.dateKey}'),
                              if (item.reason.isNotEmpty) Text('📝 原因: ${item.reason}'),
                              Text('隊伍: ${item.team}隊', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => _approveSingle(item)),
                              IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => _rejectSingle(item)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}