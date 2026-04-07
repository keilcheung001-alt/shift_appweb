// lib/pages/holidays_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../constants/constants.dart';

class HolidaysPage extends StatefulWidget {
  const HolidaysPage({super.key});

  @override
  State<HolidaysPage> createState() => _HolidaysPageState();
}

class _HolidaysPageState extends State<HolidaysPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late SharedPreferences prefs;

  Map<String, Map<String, dynamic>> publicHolidays = {};
  Map<String, Map<String, dynamic>> customHolidays = {};

  bool _loading = true;

  final List<Color> _colorOptions = [
    Colors.red,
    Colors.orange,
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHolidays();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHolidays() async {
    setState(() => _loading = true);
    prefs = await SharedPreferences.getInstance();

    // 強制匯入公眾假期（每次都做，確保有）
    await _forceImportPublicHolidays();

    // 讀取公眾假期
    final publicRaw = prefs.getString(SPK_PUBLIC_HOLIDAYS_JSON);
    if (publicRaw != null && publicRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(publicRaw) as Map<String, dynamic>;
        publicHolidays = decoded.map((key, value) =>
            MapEntry(key, Map<String, dynamic>.from(value as Map)));
      } catch (e) {
        debugPrint('⚠️ 載入公眾假期失敗: $e');
        publicHolidays = {};
      }
    }

    // 讀取自訂假期
    final customRaw = prefs.getString(SPK_CUSTOM_HOLIDAYS_JSON);
    if (customRaw != null && customRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(customRaw) as Map<String, dynamic>;
        customHolidays = decoded.map((key, value) =>
            MapEntry(key, Map<String, dynamic>.from(value as Map)));
      } catch (e) {
        debugPrint('⚠️ 載入自訂假期失敗: $e');
        customHolidays = {};
      }
    }

    setState(() => _loading = false);
  }

  Future<void> _forceImportPublicHolidays() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/holidays/hk_holidays_2026.json',
      );
      final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();

      final map = <String, Map<String, dynamic>>{};
      for (final item in list) {
        final date = item['date'] as String?;
        final name = item['name'] as String?;
        if (date != null && name != null) {
          map[date] = {
            'name': name,
            'color': Colors.red.value,
          };
        }
      }

      await prefs.setString(SPK_PUBLIC_HOLIDAYS_JSON, jsonEncode(map));
      debugPrint('✅ 強制匯入 ${map.length} 個公眾假期');
    } catch (e) {
      debugPrint('❌ 匯入公眾假期失敗：$e');
    }
  }

  Future<void> _saveHolidays() async {
    await prefs.setString(SPK_PUBLIC_HOLIDAYS_JSON, jsonEncode(publicHolidays));
    await prefs.setString(SPK_CUSTOM_HOLIDAYS_JSON, jsonEncode(customHolidays));
  }

  // 用 Dialog 新增/編輯假期
  Future<void> _openHolidayDialog({String? dateKey, String? source, String? name, Color? color}) async {
    final isEditing = dateKey != null;
    final TextEditingController nameController = TextEditingController(text: name ?? '');
    DateTime selectedDate = dateKey != null
        ? DateTime.parse(dateKey)
        : DateTime.now();
    Color selectedColor = color ?? Colors.blue;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(isEditing ? '編輯假期' : '新增假期'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setStateDialog(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '假期名稱',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('顏色：'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: _colorOptions.map((color) {
                    final isSelected = color.value == selectedColor.value;
                    return GestureDetector(
                      onTap: () => setStateDialog(() => selectedColor = color),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.black : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final newName = nameController.text.trim();
                if (newName.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('請填寫假期名稱')),
                  );
                  return;
                }
                final newDateKey = '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

                setState(() {
                  if (source == 'public') {
                    // 編輯公眾假期（公眾假期不應新增，但保留編輯）
                    if (isEditing) {
                      if (dateKey != newDateKey) {
                        publicHolidays.remove(dateKey);
                      }
                      publicHolidays[newDateKey] = {
                        'name': newName,
                        'color': selectedColor.value,
                      };
                    } else {
                      // 唔會新增公眾假期
                    }
                  } else {
                    // 自訂假期
                    if (isEditing && dateKey != newDateKey) {
                      customHolidays.remove(dateKey);
                    }
                    customHolidays[newDateKey] = {
                      'name': newName,
                      'color': selectedColor.value,
                    };
                  }
                });
                _saveHolidays();
                Navigator.pop(ctx);
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteCustomHoliday(String dateKey) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除假期'),
        content: Text('確定刪除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                customHolidays.remove(dateKey);
              });
              _saveHolidays();
              Navigator.pop(ctx);
            },
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getSortedList(Map<String, Map<String, dynamic>> map, String source) {
    final list = map.entries.map((e) => {
      'date': e.key,
      'name': e.value['name'] ?? '',
      'color': Color(e.value['color'] ?? Colors.grey.value),
      'source': source,
    }).toList();
    list.sort((a, b) => a['date'].compareTo(b['date']));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final publicList = _getSortedList(publicHolidays, 'public');
    final customList = _getSortedList(customHolidays, 'custom');

    return Scaffold(
      appBar: AppBar(
        title: const Text('假期管理'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '公眾假期'),
            Tab(text: '自訂假期'),
          ],
        ),
      ),
      body: SafeArea(  // 👈 加入 SafeArea 避免被導航條遮擋
        child: TabBarView(
          controller: _tabController,
          children: [
            // 公眾假期 (只有 Edit，冇 Delete)
            publicList.isEmpty
                ? const Center(child: Text('載入公眾假期中...'))
                : ListView.builder(
              itemCount: publicList.length,
              itemBuilder: (context, index) {
                final item = publicList[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: Container(width: 8, height: 40, color: item['color']),
                    title: Text(item['date']),
                    subtitle: Text(item['name']),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _openHolidayDialog(
                        dateKey: item['date'],
                        source: 'public',
                        name: item['name'],
                        color: item['color'],
                      ),
                    ),
                  ),
                );
              },
            ),

            // 自訂假期 (有 Edit + Delete + 新增按鈕)
            Column(
              children: [
                Expanded(
                  child: customList.isEmpty
                      ? const Center(child: Text('暫無自訂假期'))
                      : ListView.builder(
                    itemCount: customList.length,
                    itemBuilder: (context, index) {
                      final item = customList[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: Container(width: 8, height: 40, color: item['color']),
                          title: Text(item['date']),
                          subtitle: Text(item['name']),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _openHolidayDialog(
                                  dateKey: item['date'],
                                  source: 'custom',
                                  name: item['name'],
                                  color: item['color'],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteCustomHoliday(item['date']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    onPressed: () => _openHolidayDialog(source: 'custom'),
                    icon: const Icon(Icons.add),
                    label: const Text('新增自訂假期'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}