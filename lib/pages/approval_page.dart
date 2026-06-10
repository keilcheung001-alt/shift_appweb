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
import '../services/quota_service.dart';
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
  final String shift;
  final double compHours;

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
    required this.compHours,
  });
}

class PendingCancelItem {
  final String id;
  final String dateKey;
  final String team;
  final String staffId;
  final String name;
  final String nickname;
  final String reason;
  final int originalIndex;

  PendingCancelItem({
    required this.id,
    required this.dateKey,
    required this.team,
    required this.staffId,
    required this.name,
    required this.nickname,
    required this.reason,
    required this.originalIndex,
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

  // 請假核准相關
  bool _isBatchProcessing = false;
  String _homeGroup = '';
  final List<String> _allTeams = ['A', 'B', 'C', 'D'];
  late TabController _teamTabController;   // 用於隊伍分頁（請假核准）
  final Map<String, List<PendingLeaveItem>> _teamItemsMap = {'A': [], 'B': [], 'C': [], 'D': []};
  final Map<String, Set<String>> _teamSelectedIdsMap = {'A': {}, 'B': {}, 'C': {}, 'D': {}};

  // 取消申請相關
  late TabController _mainTabController;   // 用於主頁面兩個大 Tab: 請假核准, 取消申請
  List<PendingCancelItem> _pendingCancels = [];
  Set<String> _selectedCancelIds = {};
  bool _isBatchCancelProcessing = false;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _teamTabController = TabController(length: _allTeams.length, vsync: this);
    _teamTabController.addListener(_handleTeamTabChange);
    _initializePage();
  }

  @override
  void dispose() {
    _teamTabController.removeListener(_handleTeamTabChange);
    _teamTabController.dispose();
    _mainTabController.dispose();
    super.dispose();
  }

  void _handleTeamTabChange() {
    if (_teamTabController.indexIsChanging) {
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
      _teamTabController.index = initialIndex;
    }

    if (mounted) setState(() => _loading = false);
    _loadAllTeamsPendingItems();
    _loadPendingCancels();
  }

  // ==================== 請假核准相關函數 ====================
  void _loadAllTeamsPendingItems() {
    for (var team in _allTeams) {
      _loadPendingItemsForTeam(team);
    }
  }

  String _getCollectionName(String team) {
    return FIRESTORE_LEAVE_COLLECTIONS[team.toUpperCase()] ?? FIRESTORE_A_TEAM_LEAVE;
  }

  String get _currentTeam => _allTeams[_teamTabController.index];
  List<PendingLeaveItem> get _currentPendingItems => _teamItemsMap[_currentTeam] ?? [];
  Set<String> get _currentSelectedIds => _teamSelectedIdsMap[_currentTeam] ?? {};

  Future<void> _loadPendingItemsForTeam(String team) async {
    if (!_isSuperAdmin && team != _homeGroup) return;
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
        final compHoursList = (data['compHours'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [];
        final rawShift = data['shift'] as String? ?? '';
        String displayShift = rawShift.trim().isEmpty ? '未知班次' : (rawShift.trim().toUpperCase() == '休息' ? '休息日' : '${rawShift.trim().toUpperCase()} 更');
        if (statuses.length != names.length) statuses = List.filled(names.length, 'pending');
        for (int i = 0; i < names.length; i++) {
          if (statuses[i] == 'pending') {
            items.add(PendingLeaveItem(
              docId: doc.id,
              dateKey: dateKey,
              team: team,
              name: names[i],
              nickname: i < nicknames.length ? nicknames[i] : '',
              reason: i < reasons.length ? reasons[i] : '',
              days: 1,
              status: 'pending',
              index: i,
              shift: displayShift,
              compHours: i < compHoursList.length ? compHoursList[i] : 0.0,
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
      debugPrint('❌ 載入 $team 隊請假失敗: $e');
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_currentSelectedIds.contains(id)) _currentSelectedIds.remove(id);
      else _currentSelectedIds.add(id);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先選擇要批准的項目')));
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
        final item = _currentPendingItems.firstWhere((i) => i.docId == docId && i.index == index);
        itemsToNotify.add(item);
        await _updateSingleItemStatus(item, 'approved', skipReload: true);
      }
      await _sendBatchWhatsAppWithItems(itemsToNotify);
      await _loadPendingItemsForTeam(teamProcessing);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 批量批准失敗: $e')));
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
      String reasonText = item.reason.isNotEmpty ? item.reason : '無';
      if (item.compHours > 0) reasonText = '$reasonText + ${item.compHours.toStringAsFixed(1)}h 補鐘';
      return '👤 $displayName - ${item.dateKey} [${item.shift}] ($reasonText)';
    }).join('\n');
    final message = '✅ 批量批准請假\n\n👥 隊伍: $team 隊\n\n$itemsList\n\n🔍 審批人: $approverNickname';
    await Clipboard.setData(ClipboardData(text: message));
    final String encodedText = Uri.encodeComponent(message);
    Uri launchUri = Uri.parse("whatsapp://send?text=$encodedText");
    if (groupLink.contains("chat.whatsapp.com")) launchUri = Uri.parse(groupLink);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    } else {
      final fallbackUri = Uri.parse("https://api.whatsapp.com/send?text=$encodedText");
      if (await canLaunchUrl(fallbackUri)) await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      else _showErrorDialog('無法開啟 WhatsApp，訊息已複製，請手動貼上。');
    }
  }

  Future<void> _updateSingleItemStatus(PendingLeaveItem item, String newStatus, {bool skipReload = false}) async {
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
          if (hasApproved && !hasPending) overallStatus = 'approved';
          else if (hasApproved && hasPending) overallStatus = 'partial';
          else if (!hasApproved && !hasPending) overallStatus = 'rejected';
          transaction.update(docRef, {'statuses': statuses, 'status': overallStatus, 'updatedAt': FieldValue.serverTimestamp()});
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

  Future<void> _approveSingle(PendingLeaveItem item) async {
    await _updateSingleItemStatus(item, 'approved');
    await _sendApproveWhatsApp(item);
  }

  Future<void> _rejectSingle(PendingLeaveItem item) async {
    await _updateSingleItemStatus(item, 'rejected');
    await _sendRejectWhatsApp(item);
  }

  Future<void> _sendApproveWhatsApp(PendingLeaveItem item) async {
    try {
      final groupLink = await WhatsAppGroups.getLinkForTeam(item.team);
      final prefs = await SharedPreferences.getInstance();
      final approverNickname = prefs.getString(SPK_NICKNAME) ?? '管理員';
      final displayName = item.nickname.isNotEmpty ? item.nickname : item.name;
      String reasonText = item.reason.isNotEmpty ? item.reason : '無';
      if (item.compHours > 0) reasonText = '$reasonText + ${item.compHours.toStringAsFixed(1)}h 補鐘';
      final message = '✅ 已核准請假\n\n👥 隊伍: ${item.team} 隊\n👤 員工: $displayName\n📅 日期: ${item.dateKey}\n⏰ 當天班次: ${item.shift}\n📝 原因: $reasonText\n🔍 審批人: $approverNickname';
      await Clipboard.setData(ClipboardData(text: message));
      final String encodedText = Uri.encodeComponent(message);
      Uri launchUri = Uri.parse("whatsapp://send?text=$encodedText");
      if (groupLink != null && groupLink.trim().isNotEmpty) launchUri = Uri.parse(groupLink);
      if (await canLaunchUrl(launchUri)) await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      else {
        final fallbackUri = Uri.parse("https://api.whatsapp.com/send?text=$encodedText");
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) { debugPrint('WhatsApp 發送失敗: $e'); }
  }

  Future<void> _sendRejectWhatsApp(PendingLeaveItem item) async {
    try {
      final groupLink = await WhatsAppGroups.getLinkForTeam(item.team);
      final prefs = await SharedPreferences.getInstance();
      final approverNickname = prefs.getString(SPK_NICKNAME) ?? '管理員';
      final displayName = item.nickname.isNotEmpty ? item.nickname : item.name;
      String reasonText = item.reason.isNotEmpty ? item.reason : '無';
      if (item.compHours > 0) reasonText = '$reasonText + ${item.compHours.toStringAsFixed(1)}h 補鐘';
      final message = '❌ 已拒絕請假\n\n👥 隊伍: ${item.team} 隊\n👤 員工: $displayName\n📅 日期: ${item.dateKey}\n⏰ 當天班次: ${item.shift}\n📝 原因: $reasonText\n🔍 審批人: $approverNickname';
      await Clipboard.setData(ClipboardData(text: message));
      final String encodedText = Uri.encodeComponent(message);
      Uri launchUri = Uri.parse("whatsapp://send?text=$encodedText");
      if (groupLink != null && groupLink.trim().isNotEmpty) launchUri = Uri.parse(groupLink);
      if (await canLaunchUrl(launchUri)) await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      else {
        final fallbackUri = Uri.parse("https://api.whatsapp.com/send?text=$encodedText");
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) { debugPrint('WhatsApp 發送失敗: $e'); }
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

  // ==================== 取消申請相關函數 ====================
  Future<void> _loadPendingCancels() async {
    final team = _currentCancelTeam;
    if (!_isSuperAdmin && team != _homeGroup) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('pending_cancel_leaves')
          .where('team', isEqualTo: team)
          .where('status', isEqualTo: 'pending')
          .get();
      final items = <PendingCancelItem>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        items.add(PendingCancelItem(
          id: doc.id,
          dateKey: data['dateKey'] ?? '',
          team: data['team'] ?? '',
          staffId: data['staffId'] ?? '',
          name: data['name'] ?? '',
          nickname: data['nickname'] ?? '',
          reason: data['reason'] ?? '',
          originalIndex: data['originalIndex'] ?? 0,
        ));
      }
      setState(() {
        _pendingCancels = items;
        _selectedCancelIds.clear();
      });
    } catch (e) {
      debugPrint('載取消申請失敗: $e');
    }
  }

  String _currentCancelTeam = 'A';
  List<PendingCancelItem> get _currentCancelItems => _pendingCancels;
  Set<String> get _currentSelectedCancelIds => _selectedCancelIds;

  void _toggleCancelSelection(String id) {
    setState(() {
      if (_selectedCancelIds.contains(id)) _selectedCancelIds.remove(id);
      else _selectedCancelIds.add(id);
    });
  }

  void _toggleSelectAllCancel() {
    setState(() {
      if (_selectedCancelIds.length == _pendingCancels.length && _pendingCancels.isNotEmpty) {
        _selectedCancelIds.clear();
      } else {
        _selectedCancelIds.clear();
        for (var item in _pendingCancels) _selectedCancelIds.add(item.id);
      }
    });
  }

  Future<void> _batchApproveCancel() async {
    if (_selectedCancelIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先選擇要批准的取消申請')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量批准取消假期'),
        content: Text('確定批准所選的 ${_selectedCancelIds.length} 項取消申請？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('批准', style: TextStyle(color: Colors.green))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isBatchCancelProcessing = true);
    final ids = List<String>.from(_selectedCancelIds);
    try {
      for (final id in ids) {
        final item = _pendingCancels.firstWhere((i) => i.id == id);
        await _approveCancelSingle(item);
      }
      await _loadPendingCancels();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 批量批准失敗: $e')));
    } finally {
      if (mounted) setState(() => _isBatchCancelProcessing = false);
    }
  }

  Future<void> _approveCancelSingle(PendingCancelItem item) async {
    try {
      final collectionName = _getCollectionName(item.team);
      final docRef = FirebaseFirestore.instance.collection(collectionName).doc(item.dateKey);
      bool success = false;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (!doc.exists) return;
        final data = doc.data()!;
        final names = List<String>.from(data['names'] ?? []);
        final statuses = List<String>.from(data['statuses'] ?? []);
        final staffIds = List<String>.from(data['staffIds'] ?? []);
        final alHoursList = (data['alHours'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [];
        final clHoursList = (data['clHours'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [];
        final slHoursList = (data['slHours'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [];
        final compHoursList = (data['compHours'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [];

        int idx = staffIds.indexOf(item.staffId);
        if (idx == -1) idx = names.indexOf(item.name);
        if (idx == -1 || idx >= statuses.length) return;
        if (statuses[idx] != 'approved') return;

        statuses[idx] = 'cancelled';
        final hasApproved = statuses.contains('approved');
        final hasPending = statuses.contains('pending');
        String overall = 'pending';
        if (hasApproved && !hasPending) overall = 'approved';
        else if (hasApproved && hasPending) overall = 'partial';
        else if (!hasApproved && !hasPending && statuses.contains('cancelled')) overall = 'cancelled';

        transaction.update(docRef, {
          'statuses': statuses,
          'status': overall,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final alHours = idx < alHoursList.length ? alHoursList[idx] : 0.0;
        final clHours = idx < clHoursList.length ? clHoursList[idx] : 0.0;
        final slHours = idx < slHoursList.length ? slHoursList[idx] : 0.0;
        final compHours = idx < compHoursList.length ? compHoursList[idx] : 0.0;

        if (alHours > 0) await QuotaService.addLeave(staffId: item.staffId, leaveType: 'al', days: alHours / 8.0, reason: '取消假期審批');
        if (clHours > 0) await QuotaService.addLeave(staffId: item.staffId, leaveType: 'cl', days: clHours / 8.0, reason: '取消假期審批');
        if (slHours > 0) await QuotaService.addLeave(staffId: item.staffId, leaveType: 'sl', days: slHours / 8.0, reason: '取消假期審批');
        if (compHours > 0) await QuotaService.addCompTime(staffId: item.staffId, hours: compHours, reason: '取消假期審批退補鐘');
        success = true;
      });
      if (success) {
        await FirebaseFirestore.instance.collection('pending_cancel_leaves').doc(item.id).update({
          'status': 'approved',
          'processedAt': FieldValue.serverTimestamp(),
        });
        await WidgetSnapshotWriter.forceRefreshForTeam(item.team);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ 已批准取消 ${item.name} 的假期'), backgroundColor: Colors.green));
      } else {
        throw Exception('處理失敗');
      }
    } catch (e) {
      debugPrint('批准取消失敗: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失敗: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _rejectCancelSingle(PendingCancelItem item) async {
    try {
      await FirebaseFirestore.instance.collection('pending_cancel_leaves').doc(item.id).update({
        'status': 'rejected',
        'processedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已拒絕 ${item.name} 的取消申請'), backgroundColor: Colors.orange));
        await _loadPendingCancels();
      }
    } catch (e) {
      debugPrint('拒絕取消失敗: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失敗'), backgroundColor: Colors.red));
    }
  }

  // ==================== UI 構建 ====================
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('審批管理'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _mainTabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: const [
            Tab(text: '請假核准'),
            Tab(text: '取消申請'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _mainTabController,
        children: [
          _buildLeaveApprovalTab(),
          _buildCancelApprovalTab(),
        ],
      ),
    );
  }

  // 請假核准頁面（原有完整功能）
  Widget _buildLeaveApprovalTab() {
    return Column(
      children: [
        // 隊伍分頁列
        Container(
          color: Colors.grey.shade100,
          child: TabBar(
            controller: _teamTabController,
            isScrollable: true,
            indicatorColor: Colors.blue,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            tabs: _allTeams.map((team) {
              final count = _teamItemsMap[team]?.length ?? 0;
              return Tab(text: count > 0 ? '$team 隊 ($count)' : '$team 隊');
            }).toList(),
          ),
        ),
        if (_currentSelectedIds.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Text('已選擇【$_currentTeam 隊】${_currentSelectedIds.length} 項', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isBatchProcessing ? null : _batchApprove,
                  icon: _isBatchProcessing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.done_all),
                  label: Text(_isBatchProcessing ? '處理中...' : '批量批准'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _teamTabController,
            children: _allTeams.map((team) => _buildTeamListView(team)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamListView(String team) {
    if (!_isSuperAdmin && team != _homeGroup) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(Icons.lock_outline, size: 48, color: Colors.grey), SizedBox(height: 8), Text('🔒 您只能查看及審批自己所屬的隊伍', style: TextStyle(color: Colors.grey))],
        ),
      );
    }
    final items = _teamItemsMap[team] ?? [];
    final selectedIds = _teamSelectedIdsMap[team] ?? {};
    if (items.isEmpty) return const Center(child: Text('🎉 暫無待核准請假'));
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final itemId = '${item.docId}_${item.index}';
        final displayName = item.nickname.isNotEmpty ? item.nickname : item.name;
        String reasonText = item.reason.isNotEmpty ? item.reason : '無';
        if (item.compHours > 0) reasonText = '$reasonText + ${item.compHours.toStringAsFixed(1)}h 補鐘';
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              leading: Checkbox(value: selectedIds.contains(itemId), onChanged: (_) => _toggleSelection(itemId)),
              title: Row(
                children: [
                  Expanded(child: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 70),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
                    child: Text(item.shift, style: const TextStyle(fontSize: 10, color: Colors.indigo, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 1),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Row(children: [const Icon(Icons.calendar_today, size: 12, color: Colors.blueGrey), const SizedBox(width: 4), Text('日期: ${item.dateKey}', style: const TextStyle(color: Colors.black87, fontSize: 12))]),
                  if (reasonText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(children: [const Icon(Icons.edit_note, size: 12, color: Colors.blueGrey), const SizedBox(width: 4), Expanded(child: Text('原因: $reasonText', style: const TextStyle(color: Colors.black54, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis))]),
                  ],
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: const CircleAvatar(backgroundColor: Colors.green, radius: 16, child: Icon(Icons.check, color: Colors.white, size: 18)),
                    onPressed: () => _approveSingle(item),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: const CircleAvatar(backgroundColor: Colors.red, radius: 16, child: Icon(Icons.close, color: Colors.white, size: 18)),
                    onPressed: () => _rejectSingle(item),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 取消申請審批頁面
  Widget _buildCancelApprovalTab() {
    final teamOptions = _isSuperAdmin ? _allTeams : [_homeGroup];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              const Text('隊伍:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _currentCancelTeam,
                items: teamOptions.map((team) => DropdownMenuItem(value: team, child: Text('$team 隊'))).toList(),
                onChanged: (newTeam) async {
                  setState(() => _currentCancelTeam = newTeam!);
                  await _loadPendingCancels();
                },
              ),
              const Spacer(),
              if (_selectedCancelIds.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _isBatchCancelProcessing ? null : _batchApproveCancel,
                  icon: _isBatchCancelProcessing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.done_all),
                  label: const Text('批量批准'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPendingCancels),
            ],
          ),
        ),
        Expanded(
          child: _pendingCancels.isEmpty
              ? const Center(child: Text('🎉 暫無取消申請'))
              : ListView.builder(
            itemCount: _pendingCancels.length,
            itemBuilder: (ctx, i) {
              final item = _pendingCancels[i];
              final displayName = item.nickname.isNotEmpty ? item.nickname : item.name;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.orange.shade50,
                child: ListTile(
                  leading: Checkbox(
                    value: _selectedCancelIds.contains(item.id),
                    onChanged: (_) => _toggleCancelSelection(item.id),
                  ),
                  title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📅 日期: ${item.dateKey}'),
                      Text('📝 原因: ${item.reason}'),
                      const Text('⚠️ 申請取消已批核假期', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const CircleAvatar(backgroundColor: Colors.green, radius: 16, child: Icon(Icons.check, color: Colors.white, size: 18)),
                        onPressed: () async { await _approveCancelSingle(item); await _loadPendingCancels(); },
                      ),
                      IconButton(
                        icon: const CircleAvatar(backgroundColor: Colors.red, radius: 16, child: Icon(Icons.close, color: Colors.white, size: 18)),
                        onPressed: () async { await _rejectCancelSingle(item); await _loadPendingCancels(); },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}