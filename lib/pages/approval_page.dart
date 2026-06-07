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
  final String nickname;
  final String reason;
  final int days;
  final String status;
  final int index;
  final String shift; // ✅ 直接儲存來自 Firestore 的班次欄位

  PendingLeaveItem({
    required this.docId,
    required this.dateKey,
    required this.team,
    required this.name,
    required this.nickname,
    required this.reason,
    required this.days,
    required this.status,
    required this.index,
    required this.shift,
  });
}

class ApprovalPage extends StatefulWidget {
  final String? teamCode;
  const ApprovalPage({super.key, this.teamCode});

  @override
  State<ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<ApprovalPage> with SingleTickerProviderStateMixin {
  bool _canApprove = false;
  bool _loading = true;
  bool _isSuperAdmin = false;
  bool _isTeamLead = false;
  bool _isBatchProcessing = false;

  String _homeGroup = '';
  final List<String> _allTeams = ['A', 'B', 'C', 'D'];
  late TabController _tabController;

  final Map<String, List<PendingLeaveItem>> _teamItemsMap = {'A': [], 'B': [], 'C': [], 'D': []};
  final Map<String, Set<String>> _teamSelectedIdsMap = {'A': {}, 'B': {}, 'C': {}, 'D': {}};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _allTeams.length, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _initializePage();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  Future<void> _initializePage() async {
    _isSuperAdmin = await AuthUtil.getIsSuperAdmin();
    _isTeamLead = await AuthUtil.getIsTeamLead();
    _homeGroup = await AuthUtil.getHomeGroup().then((value) => value.toUpperCase());
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

    String initialTeam = 'A';
    if (_isSuperAdmin && widget.teamCode != null) {
      initialTeam = widget.teamCode!.toUpperCase();
    } else if (!_isSuperAdmin && _homeGroup.isNotEmpty) {
      initialTeam = _homeGroup;
    }

    int initialIndex = _allTeams.indexOf(initialTeam);
    if (initialIndex != -1) {
      _tabController.index = initialIndex;
    }

    if (mounted) setState(() => _loading = false);
    _loadAllTeamsPendingItems();
  }

  void _loadAllTeamsPendingItems() {
    for (var team in _allTeams) {
      _loadPendingItemsForTeam(team);
    }
  }

  String _getCollectionName(String team) {
    return FIRESTORE_LEAVE_COLLECTIONS[team.toUpperCase()] ?? FIRESTORE_A_TEAM_LEAVE;
  }

  String get _currentTeam => _allTeams[_tabController.index];
  List<PendingLeaveItem> get _currentPendingItems => _teamItemsMap[_currentTeam] ?? [];
  Set<String> get _currentSelectedIds => _teamSelectedIdsMap[_currentTeam] ?? {};

  Future<void> _loadPendingItemsForTeam(String team) async {
    if (!_isSuperAdmin && team != _homeGroup) {
      return;
    }

    try {
      final collectionName = _getCollectionName(team);
      final snapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .get(const GetOptions(source: Source.server));

      final items = <PendingLeaveItem>[];

      for (final doc in snapshot.docs) {
        if (doc.id == 'config_cycle' || doc.id == 'config_sheets') continue;

        final data = doc.data();
        final dateKey = data['dateKey'] as String? ?? doc.id;
        final names = (data['names'] as List<dynamic>?)?.cast<String>() ?? [];
        final nicknames = (data['nicknames'] as List<dynamic>?)?.cast<String>() ?? [];
        final reasons = (data['reasons'] as List<dynamic>?)?.cast<String>() ?? [];
        List<String> statuses = (data['statuses'] as List<dynamic>?)?.cast<String>() ?? [];

        final rawShift = data['shift'] as String? ?? '';
        String displayShift = '未知班次';
        if (rawShift.trim().isNotEmpty) {
          displayShift = rawShift.trim().toUpperCase() == '休息' || rawShift.trim().isEmpty
              ? '休息日'
              : '${rawShift.trim().toUpperCase()} 更';
        }

        if (statuses.length != names.length) {
          statuses = List.filled(names.length, 'pending');
        }

        for (int i = 0; i < names.length; i++) {
          final status = (i < statuses.length) ? statuses[i] : 'pending';
          if (status == 'pending') {
            items.add(PendingLeaveItem(
              docId: doc.id,
              dateKey: dateKey,
              team: team,
              name: names[i],
              nickname: i < nicknames.length ? nicknames[i] : '',
              reason: i < reasons.length ? reasons[i] : '',
              days: 1,
              status: status,
              index: i,
              shift: displayShift,
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
          _teamItemsMap[team] = items;
          _teamSelectedIdsMap[team]?.clear();
        });
      }
    } catch (e) {
      debugPrint('❌ 載入 $team 隊失敗: $e');
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_currentSelectedIds.contains(id)) {
        _currentSelectedIds.remove(id);
      } else {
        _currentSelectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_currentSelectedIds.length == _currentPendingItems.length && _currentPendingItems.isNotEmpty) {
        _currentSelectedIds.clear();
      } else {
        _currentSelectedIds.clear();
        for (var item in _currentPendingItems) {
          _currentSelectedIds.add('${item.docId}_${item.index}');
        }
      }
    });
  }

  Future<void> _batchApprove() async {
    if (_currentSelectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇要批准的項目')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量批准'),
        content: Text('確定批准所選的 ${_currentSelectedIds.length} 項請假？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('批准', style: TextStyle(color: Colors.green))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isBatchProcessing = true);

    final idsToProcess = List<String>.from(_currentSelectedIds);
    final itemsToNotify = <PendingLeaveItem>[];
    final teamProcessing = _currentTeam;

    try {
      for (final id in idsToProcess) {
        final parts = id.split('_');
        if (parts.length != 2) continue;
        final docId = parts[0];
        final index = int.parse(parts[1]);
        final item = _currentPendingItems.firstWhere(
              (i) => i.docId == docId && i.index == index,
          orElse: () => throw Exception('找不到項目'),
        );
        itemsToNotify.add(item);
        await _updateSingleItemStatus(item, 'approved', skipReload: true);
      }

      await _sendBatchWhatsAppWithItems(itemsToNotify);
      await _loadPendingItemsForTeam(teamProcessing);
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
      final displayName = item.nickname.isNotEmpty ? item.nickname : item.name;
      return '👤 $displayName - ${item.dateKey} [${item.shift}] (${item.reason.isNotEmpty ? item.reason : '無'})';
    }).join('\n');

    final message = '✅ 批量批准請假\n\n👥 隊伍: $team 隊\n\n$itemsList\n\n🔍 審批人: $approverNickname';
    await Clipboard.setData(ClipboardData(text: message));

    final String encodedText = Uri.encodeComponent(message);
    Uri launchUri = Uri.parse("whatsapp://send?text=$encodedText");

    if (groupLink.contains("chat.whatsapp.com")) {
      launchUri = Uri.parse(groupLink);
    }

    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    } else {
      final fallbackUri = Uri.parse("https://api.whatsapp.com/send?text=$encodedText");
      if (await canLaunchUrl(fallbackUri)) {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorDialog('無法開啟 WhatsApp，訊息已複製，請手動貼上。');
      }
    }
  }

  Future<void> _updateSingleItemStatus(
      PendingLeaveItem item,
      String newStatus, {
        bool skipReload = false,
      }) async {
    if (mounted) {
      setState(() {
        _teamItemsMap[item.team]?.removeWhere((i) => i.docId == item.docId && i.name == item.name);
        _teamSelectedIdsMap[item.team]?.remove('${item.docId}_${item.index}');
      });
    }

    try {
      final docRef = FirebaseFirestore.instance.collection(_getCollectionName(item.team)).doc(item.docId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docSnap = await transaction.get(docRef);
        if (!docSnap.exists) return;

        final data = docSnap.data()!;
        final names = List<String>.from(data['names'] ?? []);
        final statuses = List<String>.from(data['statuses'] ?? List.filled(names.length, 'pending'));

        if (item.index >= 0 && item.index < names.length) {
          statuses[item.index] = newStatus;

          final hasApproved = statuses.contains('approved');
          final hasPending = statuses.contains('pending');
          String overallStatus = 'pending';
          if (hasApproved && !hasPending) {
            overallStatus = 'approved';
          } else if (hasApproved && hasPending) {
            overallStatus = 'partial';
          } else if (!hasApproved && !hasPending) {
            overallStatus = 'rejected';
          }

          transaction.update(docRef, {
            'statuses': statuses,
            'status': overallStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      await WidgetSnapshotWriter.forceRefreshForTeam(item.team);
      if (!skipReload && mounted) await _loadPendingItemsForTeam(item.team);
    } catch (e) {
      debugPrint('更新狀態失敗: $e');
      if (mounted) {
        setState(() {
          if (!_teamItemsMap[item.team]!.any((i) => i.docId == item.docId && i.name == item.name)) {
            _teamItemsMap[item.team]?.add(item);
          }
        });
      }
    }
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
    await _sendApproveWhatsApp(item);
  }

  Future<void> _rejectSingle(PendingLeaveItem item) async {
    await _updateSingleItemStatus(item, 'rejected');
    await _sendRejectWhatsAppToGroup(item);
  }

  Future<void> _sendApproveWhatsApp(PendingLeaveItem item) async {
    try {
      final groupLink = await WhatsAppGroups.getLinkForTeam(item.team);
      final prefs = await SharedPreferences.getInstance();
      final approverNickname = prefs.getString(SPK_NICKNAME) ?? '管理員';
      final displayName = item.nickname.isNotEmpty ? item.nickname : item.name;

      final message = '✅ 已核准請假\n\n'
          '👥 隊伍: ${item.team} 隊\n'
          '👤 員工: $displayName\n'
          '📅 日期: ${item.dateKey}\n'
          '⏰ 當天班次: ${item.shift}\n'
          '📝 原因: ${item.reason.isNotEmpty ? item.reason : '無'}\n'
          '🔍 審批人: $approverNickname';

      await Clipboard.setData(ClipboardData(text: message));

      final String encodedText = Uri.encodeComponent(message);
      Uri launchUri = Uri.parse("whatsapp://send?text=$encodedText");
      if (groupLink != null && groupLink.trim().isNotEmpty) {
        launchUri = Uri.parse(groupLink);
      }

      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      } else {
        final fallbackUri = Uri.parse("https://api.whatsapp.com/send?text=$encodedText");
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('WhatsApp 發送失敗: $e');
    }
  }

  Future<void> _sendRejectWhatsAppToGroup(PendingLeaveItem item) async {
    try {
      final groupLink = await WhatsAppGroups.getLinkForTeam(item.team);
      final prefs = await SharedPreferences.getInstance();
      final approverNickname = prefs.getString(SPK_NICKNAME) ?? '管理員';
      final displayName = item.nickname.isNotEmpty ? item.nickname : item.name;

      final message = '❌ 已拒絕請假\n\n'
          '👥 隊伍: ${item.team} 隊\n'
          '👤 員工: $displayName\n'
          '📅 日期: ${item.dateKey}\n'
          '⏰ 當天班次: ${item.shift}\n'
          '📝 原因: ${item.reason.isNotEmpty ? item.reason : '無'}\n'
          '🔍 審批人: $approverNickname';

      await Clipboard.setData(ClipboardData(text: message));

      final String encodedText = Uri.encodeComponent(message);
      Uri launchUri = Uri.parse("whatsapp://send?text=$encodedText");
      if (groupLink != null && groupLink.trim().isNotEmpty) {
        launchUri = Uri.parse(groupLink);
      }

      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      } else {
        final fallbackUri = Uri.parse("https://api.whatsapp.com/send?text=$encodedText");
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('拒絕 WhatsApp 發送失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('請假核准大廳'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _currentSelectedIds.length == _currentPendingItems.length && _currentPendingItems.isNotEmpty
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
            ),
            onPressed: _currentPendingItems.isEmpty ? null : _toggleSelectAll,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAllTeamsPendingItems),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: _allTeams.map((team) {
            final count = _teamItemsMap[team]?.length ?? 0;
            return Tab(
              text: count > 0 ? '$team 隊 ($count)' : '$team 隊',
            );
          }).toList(),
        ),
      ),
      body: Column(
        children: [
          if (_currentSelectedIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Text('已選擇【$_currentTeam 隊】${_currentSelectedIds.length} 項',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _isBatchProcessing ? null : _batchApprove,
                    icon: _isBatchProcessing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.done_all),
                    label: Text(_isBatchProcessing ? '處理中...' : '批量批准'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _allTeams.map((team) => _buildTeamListView(team)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamListView(String team) {
    if (!_isSuperAdmin && team != _homeGroup) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('🔒 您只能查看及審批自己所屬的隊伍', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final items = _teamItemsMap[team] ?? [];
    final selectedIds = _teamSelectedIdsMap[team] ?? {};

    if (items.isEmpty) {
      return const Center(child: Text('🎉 暫無待核准請假'));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final itemId = '${item.docId}_${item.index}';
        final displayName = item.nickname.isNotEmpty ? item.nickname : item.name;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Checkbox(
              value: selectedIds.contains(itemId),
              onChanged: (_) => _toggleSelection(itemId),
            ),
            title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 14, color: Colors.blueGrey),
                    const SizedBox(width: 4),
                    Text('日期: ${item.dateKey}', style: const TextStyle(color: Colors.black87)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Text(
                        item.shift,
                        style: TextStyle(fontSize: 11, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (item.reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.edit_note, size: 16, color: Colors.blueGrey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('原因: ${item.reason}',
                            style: const TextStyle(color: Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: Colors.green,
                    radius: 14,
                    child: Icon(Icons.check, color: Colors.white, size: 16),
                  ),
                  onPressed: () => _approveSingle(item),
                ),
                IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: Colors.red,
                    radius: 14,
                    child: Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                  onPressed: () => _rejectSingle(item),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}