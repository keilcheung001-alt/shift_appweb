import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../utils/auth_util.dart';

final MethodChannel alarmChannel = MethodChannel('com.example.shift_app/alarm');

class DesktopWidgetsPage extends StatefulWidget {
  const DesktopWidgetsPage({super.key});

  @override
  State<DesktopWidgetsPage> createState() => _DesktopWidgetsPageState();
}

class _DesktopWidgetsPageState extends State<DesktopWidgetsPage> {
  bool _widgetEnabled = true;
  String _selectedTeam = 'A';
  bool _showNextShift = true;

  bool _alarmEnabled = true;

  int _advanceM = 90;
  int _advanceLM = 90;
  int _advanceA = 60;
  int _advanceLN = 120;
  int _advanceN = 120;

  bool _enableM = true;
  bool _enableLM = true;
  bool _enableA = true;
  bool _enableLN = true;
  bool _enableN = true;

  bool _loading = true;

  final Map<String, String> shiftTimes = {
    'M': '08:00',
    'LM': '08:00',
    'A': '16:00',
    'LN': '20:00',
    'N': '23:00',
  };

  // 請假快照相關
  List<Map<String, String>> _leaveMembers = [];
  bool _loadingLeave = true;
  String? _errorMessage; // 捕捉錯誤訊息用

  @override
  void initState() {
    super.initState();
    _initData();
  }

  /// 初始化整合：確保本地設定與雲端數據同步加載
  Future<void> _initData() async {
    await _loadWidgetSettings();
    await _loadInitialUserTeam();
  }

  Future<void> _loadWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _widgetEnabled = prefs.getBool('widget_enabled') ?? true;
      _selectedTeam = prefs.getString('widget_team') ?? 'A';
      _showNextShift = prefs.getBool('widget_show_next_shift') ?? true;
      _alarmEnabled = prefs.getBool('widget_alarm_enabled') ?? true;
      _advanceM = prefs.getInt('alarm_advance_M') ?? 90;
      _advanceLM = prefs.getInt('alarm_advance_LM') ?? 90;
      _advanceA = prefs.getInt('alarm_advance_A') ?? 60;
      _advanceLN = prefs.getInt('alarm_advance_LN') ?? 120;
      _advanceN = prefs.getInt('alarm_advance_N') ?? 120;
      _enableM = prefs.getBool('alarm_enable_M') ?? true;
      _enableLM = prefs.getBool('alarm_enable_LM') ?? true;
      _enableA = prefs.getBool('alarm_enable_A') ?? true;
      _enableLN = prefs.getBool('alarm_enable_LN') ?? true;
      _enableN = prefs.getBool('alarm_enable_N') ?? true;
      _loading = false;
    });
  }

  Future<void> _loadInitialUserTeam() async {
    // 如果 SharedPreferences 裡沒有存過隊伍，才用 AuthUtil 的預設隊伍
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('widget_team')) {
      final defaultTeam = await AuthUtil.getHomeGroup();
      setState(() => _selectedTeam = defaultTeam);
    }
    // 根據當前選中的隊伍撈取 Firestore 資料
    _loadLeaveSnapshot(_selectedTeam);
  }

  /// 🛠️ 核心修正：動態傳入 team，支援即時切換隊伍重刷
  Future<void> _loadLeaveSnapshot(String team) async {
    if (!mounted) return;
    setState(() {
      _loadingLeave = true;
      _errorMessage = null;
    });

    try {
      final collectionName = '${team.toLowerCase()}_team_leave';
      final snapshot = await FirebaseFirestore.instance.collection(collectionName).get();

      final members = <Map<String, String>>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name']?.toString() ?? '未命名';
        final shift = data['shift_time']?.toString() ?? '正常當班';
        members.add({'name': name, 'shift': shift});
      }

      if (mounted) {
        setState(() {
          _leaveMembers = members;
          _loadingLeave = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingLeave = false;
          _errorMessage = '載入失敗，請檢查網絡連線 ($e)';
        });
      }
    }
  }

  Future<void> _saveWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('widget_enabled', _widgetEnabled);
    await prefs.setString('widget_team', _selectedTeam);
    await prefs.setBool('widget_show_next_shift', _showNextShift);
    await prefs.setBool('widget_alarm_enabled', _alarmEnabled);
    await prefs.setInt('alarm_advance_M', _advanceM);
    await prefs.setInt('alarm_advance_LM', _advanceLM);
    await prefs.setInt('alarm_advance_A', _advanceA);
    await prefs.setInt('alarm_advance_LN', _advanceLN);
    await prefs.setInt('alarm_advance_N', _advanceN);
    await prefs.setBool('alarm_enable_M', _enableM);
    await prefs.setBool('alarm_enable_LM', _enableLM);
    await prefs.setBool('alarm_enable_A', _enableA);
    await prefs.setBool('alarm_enable_LN', _enableLN);
    await prefs.setBool('alarm_enable_N', _enableN);

    try {
      await alarmChannel.invokeMethod('syncAlarms');
    } catch (e) {
      debugPrint('底層同步跳過');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 設定已儲存')),
      );
    }
  }

  String _calculateAlarmTime(String startTimeStr, int earlyMinutes) {
    try {
      final parts = startTimeStr.split(':');
      final int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);
      int totalMins = hour * 60 + minute - earlyMinutes;
      if (totalMins < 0) totalMins += 24 * 60;
      final int finalHour = totalMins ~/ 60;
      final int finalMinute = totalMins % 60;
      return '${finalHour.toString().padLeft(2, '0')}:${finalMinute.toString().padLeft(2, '0')}';
    } catch (e) {
      return startTimeStr;
    }
  }

  /// 👑 優化組件：引入具名參數、SliderTheme、四捨五入滑塊
  Widget _buildFlexibleAlarmSlider({
    required String title,
    required String startTime,
    required bool isEnabled,
    required int currentAdvance,
    required Color color,
    required ValueChanged<bool> onToggle,
    required ValueChanged<int> onSlider,
  }) {
    String ringingTime = _calculateAlarmTime(startTime, currentAdvance);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Transform.scale(scale: 0.85, child: Switch(value: isEnabled, activeColor: color, onChanged: onToggle)),
            ],
          ),
          if (!isEnabled) ...[
            const Padding(padding: EdgeInsets.only(top: 4, bottom: 8), child: Text('❌ 呢個班次嘅鬧鐘閂咗', style: TextStyle(color: Colors.red, fontSize: 12))),
          ] else ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(currentAdvance == 0 ? '設定：準時響' : '設定：提早 $currentAdvance 分鐘響', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                Text('🎯 鬧鐘: $ringingTime (開工: $startTime)', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
              ),
              child: Slider(
                value: currentAdvance.toDouble(),
                min: 0,
                max: 240,
                divisions: 48,
                label: '提早 $currentAdvance 分鐘',
                activeColor: color,
                inactiveColor: color.withOpacity(0.15),
                onChanged: (val) => onSlider(val.round()), // 🛠️ round() 解決拖動斷點精準度
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFFFFcf7),
      appBar: AppBar(
        title: const Text('桌面小工具與鬧鐘設定', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 桌面小工具狀態
            Card(
              color: const Color(0xFFFFF9F2),
              elevation: 0,
              shape: RoundedRectangleBorder(side: BorderSide(color: Colors.orange.shade100), borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.apps, color: Colors.green),
                        SizedBox(width: 8),
                        Text('桌面小工具狀態', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: _widgetEnabled,
                          activeColor: Colors.green,
                          onChanged: (val) => setState(() => _widgetEnabled = val ?? true),
                        ),
                        const Text('已啟用', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. 選擇顯示隊伍
            const Text('選擇顯示隊伍', style: TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTeam,
                  isExpanded: true,
                  items: ['A', 'B', 'C', 'D'].map((t) => DropdownMenuItem(value: t, child: Text('$t 隊'))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedTeam = val);
                      _loadLeaveSnapshot(val); // 🛠️ 核心修正：切換下拉選單時，同步重刷 Firestore 數據！
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. 顯示內容選項
            const Text('顯示內容選項', style: TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 6),
            Card(
              color: const Color(0xFFFFF9F2),
              elevation: 0,
              shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
              child: CheckboxListTile(
                title: const Text('顯示未來班次 (今日+2日)', style: TextStyle(fontSize: 14)),
                value: _showNextShift,
                activeColor: const Color(0xFF8D6E63),
                onChanged: (val) => setState(() => _showNextShift = val ?? true),
              ),
            ),
            const SizedBox(height: 20),

            // 4. 廠房班次獨立鬧鐘設定
            const Text('⏰ 廠房班次獨立鬧鐘設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFFFFF9F2),
              elevation: 2,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('開啟返工智能鬧鐘功能', style: TextStyle(fontWeight: FontWeight.bold)),
                    value: _alarmEnabled,
                    activeColor: Colors.orange,
                    onChanged: (val) => setState(() => _alarmEnabled = val),
                  ),
                  if (_alarmEnabled) ...[
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider(title: '早班 (M) 鬧鐘', startTime: shiftTimes['M']!, isEnabled: _enableM, currentAdvance: _advanceM, color: const Color(0xFF1E88E5), onToggle: (val) => setState(() => _enableM = val), onSlider: (val) => setState(() => _advanceM = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider(title: 'L早班 (LM) 鬧鐘', startTime: shiftTimes['LM']!, isEnabled: _enableLM, currentAdvance: _advanceLM, color: const Color(0xFF43A047), onToggle: (val) => setState(() => _enableLM = val), onSlider: (val) => setState(() => _advanceLM = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider(title: '中班 (A) 鬧鐘', startTime: shiftTimes['A']!, isEnabled: _enableA, currentAdvance: _advanceA, color: const Color(0xFFFB8C00), onToggle: (val) => setState(() => _enableA = val), onSlider: (val) => setState(() => _advanceA = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider(title: 'L夜班 (LN) 鬧鐘', startTime: shiftTimes['LN']!, isEnabled: _enableLN, currentAdvance: _advanceLN, color: const Color(0xFF00838F), onToggle: (val) => setState(() => _enableLN = val), onSlider: (val) => setState(() => _advanceLN = val)),
                    const Divider(height: 1),
                    _buildFlexibleAlarmSlider(title: '夜班 (N) 鬧鐘', startTime: shiftTimes['N']!, isEnabled: _enableN, currentAdvance: _advanceN, color: const Color(0xFF7B1FA2), onToggle: (val) => setState(() => _enableN = val), onSlider: (val) => setState(() => _advanceN = val)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 保存按鈕
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _saveWidgetSettings,
                icon: const Icon(Icons.save),
                label: const Text('儲存設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),

            // 5. 當班團隊成員網上快照區域
            const Text('📋 當班團隊成員網上快照', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildLeaveSnapshotSection(),
          ],
        ),
      ),
    );
  }

  /// 🛠️ 抽出快照 UI 邏輯，增加 Error 狀態渲染提升健壯度
  Widget _buildLeaveSnapshotSection() {
    if (_loadingLeave) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Card(
        color: Colors.red.shade50,
        shape: RoundedRectangleBorder(side: BorderSide(color: Colors.red.shade200), borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13))),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.red),
                onPressed: () => _loadLeaveSnapshot(_selectedTeam),
              )
            ],
          ),
        ),
      );
    }

    if (_leaveMembers.isEmpty) {
      return const SizedBox(
        width: double.infinity,
        child: Card(
          elevation: 0,
          color: Color(0xFFF5F5F5),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('🎉 今日無人請假 / 所有人正常當班', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _leaveMembers.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (ctx, idx) {
          final m = _leaveMembers[idx];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade50,
              child: const Icon(Icons.person, color: Colors.orange),
            ),
            title: Text(m['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(m['shift']!, style: TextStyle(color: m['shift']!.contains('請假') ? Colors.red : Colors.blueGrey)),
          );
        },
      ),
    );
  }
}