// lib/services/google_sheets_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/constants.dart';

class GoogleSheetsService {

  // 獲取某隊的實際使用 URL（優先使用者自訂，否則用預設）
  static Future<String?> getEffectiveScriptUrl(String team) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'custom_script_url_${team.toUpperCase()}';
    final customUrl = prefs.getString(key);
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }
    return APPS_SCRIPT_URLS[team.toUpperCase()];
  }

  static String? getDefaultScriptUrl(String team) {
    return APPS_SCRIPT_URLS[team.toUpperCase()];
  }

  // 新版本：接收一個 Map，包含所有請假資料
  static Future<Map<String, dynamic>> uploadLeaveRecord({
    required Map<String, dynamic> firestoreData,
  }) async {
    try {
      final team = firestoreData['team'] ?? 'A';
      final url = await getEffectiveScriptUrl(team);
      if (url == null) {
        return {'success': false, 'message': '找不到 $team 組的 Apps Script URL (請檢查設定)'};
      }

      final dateKey = firestoreData['dateKey'] as String;

      // 1. 獲取下一個序號
      final checkResponse = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getNextIndex', 'dateKey': dateKey}),
      );

      final checkResult = jsonDecode(checkResponse.body);
      final int nextIndex = checkResult['nextIndex'] ?? 1;

      // 2. 組裝要上傳的資料（保留全部原有欄位）
      final Map<String, dynamic> postData = {
        'action': 'addLeaveRecord',
        'applicationIndex': nextIndex,
        'userName': firestoreData['userName'] ?? '',
        'nickname': firestoreData['nickname'] ?? '',
        'employeeId': firestoreData['employeeId'] ?? '',
        'positionCode': firestoreData['positionCode'] ?? '',
        'dateKey': dateKey,
        'reason': firestoreData['reason'] ?? '',
        'days': firestoreData['days'] ?? 1,
        'status': firestoreData['status'] ?? 'pending',
        'timestamp': DateTime.now().toIso8601String(),
      };

      debugPrint('[GoogleSheets] 上傳數據至 $team ($url): $postData');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(postData),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return {'success': true, 'message': '✅ 成功上傳到 $team 組 Google Sheets'};
        } else {
          return {'success': false, 'message': '❌ Apps Script 返回錯誤: ${result['message']}'};
        }
      } else {
        return {'success': false, 'message': '❌ HTTP 錯誤: ${response.statusCode}'};
      }
    } catch (e) {
      debugPrint('[GoogleSheets] 上傳錯誤: $e');
      return {'success': false, 'message': '❌ 上傳錯誤: $e'};
    }
  }

  static Future<Map<String, dynamic>> testConnection(String team) async {
    try {
      final url = await getEffectiveScriptUrl(team);
      if (url == null) return {'success': false, 'message': '找不到 URL'};
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'test'}),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return {'success': body['success'] == true, 'message': body['message'] ?? 'OK'};
      }
      return {'success': false, 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, Map<String, dynamic>>> getSheetsConfigStatus() async {
    final status = <String, Map<String, dynamic>>{};
    final prefs = await SharedPreferences.getInstance();
    for (final team in ['A', 'B', 'C', 'D']) {
      final customKey = 'custom_script_url_$team';
      final customUrl = prefs.getString(customKey);
      final defaultUrl = APPS_SCRIPT_URLS[team];
      status[team] = {
        'configured': (customUrl != null && customUrl.isNotEmpty) || defaultUrl != null,
        'customUrl': customUrl,
        'defaultUrl': defaultUrl,
      };
    }
    return status;
  }

  static Future<bool> saveCustomUrl(String team, String url) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'custom_script_url_${team.toUpperCase()}';
    if (url.trim().isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, url.trim());
    }
    return true;
  }
}