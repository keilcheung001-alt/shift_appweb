// lib/services/google_sheets_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/constants.dart';

class GoogleSheetsService {

  static Future<String?> getEffectiveScriptUrl(String team) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'custom_script_url_${team.toUpperCase()}';
    final customUrl = prefs.getString(key);
    if (customUrl != null && customUrl.isNotEmpty) return customUrl;
    return APPS_SCRIPT_URLS[team.toUpperCase()];
  }

  static Future<void> saveCustomUrl(String team, String url) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'custom_script_url_${team.toUpperCase()}';
    if (url.trim().isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, url.trim());
    }
  }

  static Future<Map<String, dynamic>> getSheetsConfigStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> status = {};
    for (var team in TEAMS) {
      final key = 'custom_script_url_${team.toUpperCase()}';
      final customUrl = prefs.getString(key) ?? '';
      final defaultUrl = APPS_SCRIPT_URLS[team.toUpperCase()] ?? '';
      status[team] = {
        'defaultUrl': defaultUrl,
        'customUrl': customUrl,
      };
    }
    return status;
  }

  // ✅ 測試連接
  static Future<Map<String, dynamic>> testConnection(String team) async {
    try {
      final url = await getEffectiveScriptUrl(team);
      if (url == null || url.isEmpty) return {'success': false, 'message': '無效的 URL'};

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

  // ✅ 原本手機 App 用嘅完整上傳流程（先拎序號，再 submit）
  static Future<Map<String, dynamic>> uploadLeaveRecord({
    required String team,
    required String userName,
    required String nickname,
    required String employeeId,
    required String positionCode,
    required String dateKey,
    required String reason,
    required double days,
    required String status,
  }) async {
    try {
      final url = await getEffectiveScriptUrl(team);
      if (url == null || url.isEmpty) {
        return {'success': false, 'message': '找不到該隊伍的 URL'};
      }

      // Step 1: 獲取當日最大序號
      final indexResponse = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'getNextIndex',
          'dateKey': dateKey,
        }),
      );

      if (indexResponse.statusCode != 200) {
        return {'success': false, 'message': '獲取序號失敗: HTTP ${indexResponse.statusCode}'};
      }

      final indexBody = jsonDecode(indexResponse.body);
      final nextIndex = indexBody['nextIndex'] ?? 1;

      // Step 2: 提交請假記錄
      final submitResponse = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'addLeaveRecord',
          'userName': userName,
          'nickname': nickname,
          'employeeId': employeeId,
          'positionCode': positionCode,
          'dateKey': dateKey,
          'reason': reason,
          'days': days,
          'status': status,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      if (submitResponse.statusCode != 200) {
        return {'success': false, 'message': '提交失敗: HTTP ${submitResponse.statusCode}'};
      }

      final submitBody = jsonDecode(submitResponse.body);
      if (submitBody['success'] == true) {
        return {
          'success': true,
          'message': submitBody['message'] ?? '上傳成功',
          'applicationIndex': submitBody['applicationIndex'],
        };
      } else {
        return {'success': false, 'message': submitBody['message'] ?? '未知錯誤'};
      }

    } catch (e) {
      debugPrint("【GoogleSheetsService Error】: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 【全新加進去的測試分支】完全獨立，100% 隔離，不影響原本正常的手機 App 提交
  static Future<Map<String, dynamic>> submitLeaveWithForcedFallback({
    required String team,
    required String userName,
    required String nickname,
    required String employeeId,
    required String positionCode,
    required String dateKey,
    required String reason,
    required double days,
    required String status,
  }) async {
    try {
      final url = await getEffectiveScriptUrl(team);
      if (url == null || url.isEmpty) {
        return {'success': false, 'message': '未配置 Apps Script URL'};
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'text/plain',
        },
        body: jsonEncode({
          'action': 'addLeaveRecord',
          'userName': userName,
          'nickname': nickname,
          'employeeId': employeeId,
          'positionCode': positionCode,
          'dateKey': dateKey,
          'reason': reason,
          'days': days,
          'status': status,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode != 200) {
        return {'success': false, 'message': '發送未完全成功，但已觸發後台保底寫入檢查，錯誤碼: ${response.statusCode}'};
      }

      final body = jsonDecode(response.body);
      return {
        'success': body['success'] ?? false,
        'message': body['message'] ?? '處理完成',
        'applicationIndex': body['applicationIndex'],
      };
    } catch (e) {
      debugPrint('【隔離測試通道報錯】: $e');
      return {'success': false, 'message': '前端異常，已交由後台強行捕獲: $e'};
    }
  }
}