// lib/services/google_sheets_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class GoogleSheetsService {
  // 此為四組 URL 的完整定義
  static const Map<String, String> _scriptUrls = {
    'A': 'https://script.google.com/macros/s/AKfycbygcFMluPzyScBZ-KjflhcHdXkzN02b-rwx7PSfpEI1ztRiIxh4XWe6uoit6tq6MZy3Vg/exec',
    'B': 'https://script.google.com/macros/s/AKfycbzBsnwF_XwUtwgUzQDSLu7AgLbHOe0PtgtbTPQm2uYSSSLRF7QtwAPvhnBj61oTlWCa/exec',
    'C': 'https://script.google.com/macros/s/AKfycbxghqBmz9dlGAaj5mw1_xNm5IaeBr8eeww0bqFYFHKs15HwcXbhq6hZkTxTR6TiiokUig/exec',
    'D': 'https://script.google.com/macros/s/AKfycbz_UljpGPFvkvboykcR5mBMOy-Pf7uo9hkTFfnstBi8kNKLZGdIgMS0DdEEKQcdEPzWxg/exec',
  };

  static String? getScriptUrl(String team) => _scriptUrls[team.toUpperCase()];

  // 上傳請假記錄的完整功能
  static Future<Map<String, dynamic>> uploadLeaveRecord({
    required String team,
    required String userName,
    required String nickname,
    required String employeeId,
    required String positionCode,
    required String dateKey,
    required String reason,
    required int days,
    required String status,
  }) async {
    try {
      final url = getScriptUrl(team);
      if (url == null) {
        return {'success': false, 'message': '找不到 $team 組的 Apps Script URL'};
      }

      final Map<String, dynamic> postData = {
        'action': 'addLeaveRecord',
        'dateKey': dateKey,
        'userName': userName,
        'nickname': nickname,
        'employeeId': employeeId,
        'positionCode': positionCode,
        'reason': reason,
        'days': days,
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
      };

      debugPrint('[GoogleSheets] 開始上傳到 $team 隊: $postData');

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

  // 測試連接功能
  static Future<Map<String, dynamic>> testConnection(String team) async {
    try {
      final url = getScriptUrl(team);
      if (url == null) return {'success': false, 'message': '找不到 URL'};
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'test'}),
      );
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // 獲取配置狀態
  static Future<Map<String, Map<String, dynamic>>> getSheetsConfigStatus() async {
    final status = <String, Map<String, dynamic>>{};
    for (final team in ['A', 'B', 'C', 'D']) {
      status[team] = {
        'configured': getScriptUrl(team) != null,
        'hasSheetId': true,
        'hasApiKey': true,
        'sheetId': '使用 Apps Script',
      };
    }
    return status;
  }

  static Future<List<Map<String, dynamic>>> downloadTeamLeaveRecords(String team) async => [];
  static Future<void> initializeApiKey() async {}
}