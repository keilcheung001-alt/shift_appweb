// lib/services/google_sheets_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class GoogleSheetsService {
  // 呢度已經幫你改晒做 /exec，直接複製呢段代碼覆蓋你原本嗰個
  static const Map<String, String> _scriptUrls = {
    'A': 'https://script.google.com/macros/s/AKfycbwtqob60eGhFsYPudq0uC8KIHROM6hDqAUpmazNN0z0/exec',
    'B': 'https://script.google.com/macros/s/AKfycbxByKt2MZkGbARGQ6N6g3SCe_9wipp8_ok99hlfrd9g/exec',
    'C': 'https://script.google.com/macros/s/AKfycbx66qsTvL-9X2V0eV3jMRrmJBjx2F2Jv4CTjKbkyExh/exec',
    'D': 'https://script.google.com/macros/s/AKfycbxByKt2MZkGbARGQ6N6g3SCe_9wipp8_ok99hlfrd9g/exec',
  };

  static String? getScriptUrl(String team) => _scriptUrls[team.toUpperCase()];

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

      // 1. 先從 Apps Script 獲取當天已有的記錄總數，用於計算下一個序號
      final checkResponse = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getNextIndex', 'dateKey': dateKey}),
      );

      final checkResult = jsonDecode(checkResponse.body);
      final int nextIndex = checkResult['nextIndex'] ?? 1;

      // 2. 依照要求：將「當天序號」作為第 1 個欄位，確保總共 10 個欄位
      final Map<String, dynamic> postData = {
        'action': 'addLeaveRecord',
        'applicationIndex': nextIndex, // 第 1 欄
        'userName': userName,          // 第 2 欄
        'nickname': nickname,          // 第 3 欄
        'employeeId': employeeId,      // 第 4 欄
        'positionCode': positionCode,  // 第 5 欄
        'dateKey': dateKey,            // 第 6 欄
        'reason': reason,              // 第 7 欄
        'days': days,                  // 第 8 欄
        'status': status,              // 第 9 欄
        'timestamp': DateTime.now().toIso8601String(), // 第 10 欄
      };

      debugPrint('[GoogleSheets] 上傳數據至 $team: $postData');

      // 3. 正式發送數據到 Apps Script
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

  static Future<Map<String, Map<String, dynamic>>> getSheetsConfigStatus() async {
    final status = <String, Map<String, dynamic>>{};
    for (final team in ['A', 'B', 'C', 'D']) {
      status[team] = {
        'configured': getScriptUrl(team) != null,
      };
    }
    return status;
  }
}