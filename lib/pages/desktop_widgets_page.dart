import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DesktopWidgetsPage extends StatefulWidget {
  const DesktopWidgetsPage({super.key});

  @override
  State<DesktopWidgetsPage> createState() => _DesktopWidgetsPageState();
}

class _DesktopWidgetsPageState extends State<DesktopWidgetsPage> {
  // 核心鬧鐘控制狀態變數
  bool _isProcessAlarmEnabled = true;
  bool _isEquipmentAlarmEnabled = true;
  bool _isSafetyAlarmEnabled = true;
  double _alarmRangeMinutes = 60.0;

  // 🔔 鬧鐘測試與班次資料比對視窗
  void _testTriggerAlarm(String type, bool isEnabled, String staffName, String shiftTime) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(isEnabled ? Icons.alarm : Icons.volume_off,
                 color: isEnabled ? const Color(0xFF4A55A2) : Colors.grey),
            const SizedBox(width: 8),
            Text('$type 鬧鐘測試'),
          ],
        ),
        content: Text(
          isEnabled
              ? '【發送成功】\n'
                '當前上班人員: $staffName ($shiftTime)\n'
                '系統已偵測到該類別異常，將於 ${_alarmRangeMinutes.round()} 分鐘內向當班人員發送通知。'
              : '【已攔截】\n'
                '當前上班人員: $staffName ($shiftTime)\n'
                '由於您已關閉此類別的自主控制開關，該異常已被屏蔽，不會發出通知。'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        title: const Text('桌面小工具與鬧鐘'),
        backgroundColor: const Color(0xFF4A55A2),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 頂部核心控制說明卡片
          Card(
            elevation: 0,
            color: Colors.indigo.withOpacity(0.05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.alarm_on, color: Color(0xFF3F51B5), size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '總鬧鐘自主權控制系統：您可以獨立切換各類別開關，並自由調整通知時效範圍。',
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section 1: 獨立類別開關控制
          const Text(
            '獨立鬧鐘類別控制',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFF0F0F0))),
            child: Column(
              children: [
                SwitchListTile(
                  activeColor: const Color(0xFF3F51B5),
                  title: const Text('製程異常鬧鐘 (Process Alarms)'),
                  subtitle: const Text('獨立切換製程線路參數警報'),
                  value: _isProcessAlarmEnabled,
                  onChanged: (val) => setState(() => _isProcessAlarmEnabled = val),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  activeColor: const Color(0xFF3F51B5),
                  title: const Text('設備運作鬧鐘 (Equipment Alarms)'),
                  subtitle: const Text('獨立切換運轉機組與槽體警報'),
                  value: _isEquipmentAlarmEnabled,
                  onChanged: (val) => setState(() => _isEquipmentAlarmEnabled = val),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  activeColor: const Color(0xFF3F51B5),
                  title: const Text('安全連鎖鬧鐘 (Safety Interlocks)'),
                  subtitle: const Text('最高級別安全跳車通知開關'),
                  value: _isSafetyAlarmEnabled,
                  onChanged: (val) => setState(() => _isSafetyAlarmEnabled = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section 2: 0-240 分鐘自主調控範圍滑塊
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '鬧鐘有效延遲範圍',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3F51B5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_alarmRangeMinutes.round()} 分鐘',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFF0F0F0))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
              child: Column(
                children: [
                  Slider(
                    value: _alarmRangeMinutes,
                    min: 0.0,
                    max: 240.0,
                    divisions: 48, // 每 5 分鐘一格
                    activeColor: const Color(0xFF3F51B5),
                    inactiveColor: Colors.grey.shade300,
                    onChanged: (value) {
                      setState(() {
                        _alarmRangeMinutes = value;
                      });
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0 分 (即時)', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        Text('120 分', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        Text('240 分 (4小時)', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Section 3: 🔄 從 Firestore 快照拉取上班時間並進行鬧鐘測試
          const Text(
            '當班人員網上數據快照 (Firestore Stream)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 8),

          StreamBuilder<QuerySnapshot>(
            // 監聽網上 Firestore 儲存團隊當班/排班時間的 Collection (請更換為你實際的 collection 名稱，例如 'team_shifts' 或 'users')
            stream: FirebaseFirestore.instance.collection('team_shifts').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('網上數據載入錯誤', style: TextStyle(color: Colors.red)),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(color: Color(0xFF3F51B5)),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFF0F0F0))),
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('目前網上沒有當班人員資料', style: TextStyle(color: Colors.black54)),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  // 從網上 Firestore 欄位讀取名字與上班時間
                  final String name = data['name'] ?? '未知人員';
                  final String shiftTime = data['shift_time'] ?? '未排班';

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFF0F0F0))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 4),
                                Text('上班時間: $shiftTime', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                              ],
                            ),
                          ),
                          // 點擊此按鈕，直接帶入該當班人員的資料去進行鬧鐘生效比對測試
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A55A2),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              _testTriggerAlarm('製程異常', _isProcessAlarmEnabled, name, shiftTime);
                            },
                            child: const Text('測試鬧鐘', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}