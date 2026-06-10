// lib/services/leave_delete_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shift_app/services/quota_service.dart';
import 'package:shift_app/utils/auth_util.dart';

class LeaveDeleteService {
  /// 獲取當日請假人員列表（用嚟俾管理員揀）
  static List<Map<String, dynamic>> getLeavePeopleForDay(
      Map<String, Map<String, dynamic>> teamLeave,
      DateTime day,
      ) {
    final String dk = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final info = teamLeave[dk];
    if (info == null) return [];

    final names = (info['names'] as List<dynamic>?)?.cast<String>() ?? [];
    final nicknames = (info['nicknames'] as List<dynamic>?)?.cast<String>() ?? [];
    final reasons = (info['reasons'] as List<dynamic>?)?.cast<String>() ?? [];
    final statuses = (info['statuses'] as List<dynamic>?)?.cast<String>() ?? [];
    final alHoursList = (info['alHours'] as List<dynamic>?)?.cast<double>() ?? [];
    final clHoursList = (info['clHours'] as List<dynamic>?)?.cast<double>() ?? [];
    final slHoursList = (info['slHours'] as List<dynamic>?)?.cast<double>() ?? [];
    final compHoursList = (info['compHours'] as List<dynamic>?)?.cast<double>() ?? [];

    final List<Map<String, dynamic>> people = [];
    for (int i = 0; i < names.length; i++) {
      people.add({
        'name': names[i],
        'nickname': i < nicknames.length ? nicknames[i] : '',
        'reason': i < reasons.length ? reasons[i] : '',
        'status': i < statuses.length ? statuses[i] : 'pending',
        'alHours': i < alHoursList.length ? alHoursList[i] : 0.0,
        'clHours': i < clHoursList.length ? clHoursList[i] : 0.0,
        'slHours': i < slHoursList.length ? slHoursList[i] : 0.0,
        'compHours': i < compHoursList.length ? compHoursList[i] : 0.0,
        'index': i,
      });
    }
    return people;
  }

  /// 刪除自己嘅 pending/rejected 請假（員工用）
  static Future<bool> deleteMyLeave({
    required String teamCode,
    required String myName,
    required DateTime day,
    required VoidCallback onSuccess,
    required VoidCallback onRefresh,
  }) async {
    try {
      final String dk = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final collection = FirebaseFirestore.instance.collection(
          teamCode == 'A' ? 'a_team_leave' :
          teamCode == 'B' ? 'b_team_leave' :
          teamCode == 'C' ? 'c_team_leave' : 'd_team_leave'
      );
      final docRef = collection.doc(dk);

      // 先取得要退還的配額資料（在 transaction 外讀取，避免之後找不到）
      final docSnap = await docRef.get();
      if (!docSnap.exists) return false;
      final data = docSnap.data()!;
      final List<dynamic> names = data['names'] ?? [];
      final List<dynamic> statuses = data['statuses'] ?? [];
      final List<dynamic> alHoursList = data['alHours'] ?? [];
      final List<dynamic> clHoursList = data['clHours'] ?? [];
      final List<dynamic> slHoursList = data['slHours'] ?? [];
      final List<dynamic> compHoursList = data['compHours'] ?? [];

      int targetIndex = -1;
      for (int i = 0; i < names.length; i++) {
        if (names[i] == myName) {
          final status = i < statuses.length ? statuses[i] : 'pending';
          if (status == 'pending' || status == 'rejected') {
            targetIndex = i;
            break;
          }
        }
      }
      if (targetIndex == -1) return false;

      final staffId = await AuthUtil.getStaffId();
      final alHours = targetIndex < alHoursList.length ? (alHoursList[targetIndex] as num).toDouble() : 0.0;
      final clHours = targetIndex < clHoursList.length ? (clHoursList[targetIndex] as num).toDouble() : 0.0;
      final slHours = targetIndex < slHoursList.length ? (slHoursList[targetIndex] as num).toDouble() : 0.0;
      final compHours = targetIndex < compHoursList.length ? (compHoursList[targetIndex] as num).toDouble() : 0.0;

      // 執行 transaction 刪除記錄
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (!doc.exists) return;
        final currentData = doc.data()!;
        final currentNames = List<String>.from(currentData['names'] ?? []);
        final currentStatuses = List<String>.from(currentData['statuses'] ?? []);

        // 重新確認索引（防止期間被其他操作變動）
        int currentIndex = -1;
        for (int i = 0; i < currentNames.length; i++) {
          if (currentNames[i] == myName) {
            final s = i < currentStatuses.length ? currentStatuses[i] : 'pending';
            if (s == 'pending' || s == 'rejected') {
              currentIndex = i;
              break;
            }
          }
        }
        if (currentIndex == -1) return;

        final newNames = List<String>.from(currentNames)..removeAt(currentIndex);
        final newNicknames = List<String>.from(currentData['nicknames'] ?? [])..removeAt(currentIndex);
        final newReasons = List<String>.from(currentData['reasons'] ?? [])..removeAt(currentIndex);
        final newStatuses = List<String>.from(currentStatuses)..removeAt(currentIndex);
        final newStaffIds = List<String>.from(currentData['staffIds'] ?? [])..removeAt(currentIndex);
        final newAlHours = List<double>.from((currentData['alHours'] as List? ?? []).map((e) => (e as num).toDouble()))..removeAt(currentIndex);
        final newClHours = List<double>.from((currentData['clHours'] as List? ?? []).map((e) => (e as num).toDouble()))..removeAt(currentIndex);
        final newSlHours = List<double>.from((currentData['slHours'] as List? ?? []).map((e) => (e as num).toDouble()))..removeAt(currentIndex);
        final newCompHours = List<double>.from((currentData['compHours'] as List? ?? []).map((e) => (e as num).toDouble()))..removeAt(currentIndex);

        final bool hasApproved = newStatuses.contains('approved');
        final bool hasPending = newStatuses.contains('pending');
        String overallStatus = 'pending';
        if (hasApproved && !hasPending) overallStatus = 'approved';
        else if (hasApproved && hasPending) overallStatus = 'partial';

        if (newNames.isEmpty) {
          transaction.delete(docRef);
        } else {
          transaction.update(docRef, {
            'names': newNames,
            'nicknames': newNicknames,
            'reasons': newReasons,
            'statuses': newStatuses,
            'staffIds': newStaffIds,
            'alHours': newAlHours,
            'clHours': newClHours,
            'slHours': newSlHours,
            'compHours': newCompHours,
            'status': overallStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      // 退還配額（transaction 成功後）
      if (staffId.isNotEmpty) {
        if (alHours > 0) {
          await QuotaService.addLeave(staffId: staffId, leaveType: 'al', days: alHours / 8.0, reason: '取消請假');
        }
        if (clHours > 0) {
          await QuotaService.addLeave(staffId: staffId, leaveType: 'cl', days: clHours / 8.0, reason: '取消請假');
        }
        if (slHours > 0) {
          await QuotaService.addLeave(staffId: staffId, leaveType: 'sl', days: slHours / 8.0, reason: '取消請假');
        }
        if (compHours > 0) {
          await QuotaService.addCompTime(staffId: staffId, hours: compHours, reason: '取消請假退補鐘');
        }
      }

      onSuccess();
      onRefresh();
      return true;
    } catch (e) {
      debugPrint('deleteMyLeave error: $e');
      return false;
    }
  }

  /// 管理員強制刪除任何請假記錄（已修復索引錯誤及退 quota）
  static Future<bool> adminForceDelete({
    required String teamCode,
    required DateTime day,
    required int targetIndex,
    required VoidCallback onRefresh,
  }) async {
    try {
      final String dk = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final collection = FirebaseFirestore.instance.collection(
          teamCode == 'A' ? 'a_team_leave' :
          teamCode == 'B' ? 'b_team_leave' :
          teamCode == 'C' ? 'c_team_leave' : 'd_team_leave'
      );
      final docRef = collection.doc(dk);

      // 先讀取要刪除的資料（在 transaction 外，避免之後找不到）
      final docSnap = await docRef.get();
      if (!docSnap.exists) return false;
      final data = docSnap.data()!;
      final List<dynamic> names = data['names'] ?? [];
      if (targetIndex < 0 || targetIndex >= names.length) {
        debugPrint('adminForceDelete: 索引無效 (targetIndex=$targetIndex, length=${names.length})');
        return false;
      }

      final staffId = (data['staffIds'] != null && targetIndex < (data['staffIds'] as List).length)
          ? (data['staffIds'] as List)[targetIndex] as String? ?? ''
          : '';
      final List<dynamic> alHoursList = data['alHours'] ?? [];
      final List<dynamic> clHoursList = data['clHours'] ?? [];
      final List<dynamic> slHoursList = data['slHours'] ?? [];
      final List<dynamic> compHoursList = data['compHours'] ?? [];

      final alHours = targetIndex < alHoursList.length ? (alHoursList[targetIndex] as num).toDouble() : 0.0;
      final clHours = targetIndex < clHoursList.length ? (clHoursList[targetIndex] as num).toDouble() : 0.0;
      final slHours = targetIndex < slHoursList.length ? (slHoursList[targetIndex] as num).toDouble() : 0.0;
      final compHours = targetIndex < compHoursList.length ? (compHoursList[targetIndex] as num).toDouble() : 0.0;

      // Transaction 刪除記錄
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (!doc.exists) return;
        final currentData = doc.data()!;
        final currentNames = List<String>.from(currentData['names'] ?? []);
        if (targetIndex >= currentNames.length) return; // 再次檢查

        final newNames = List<String>.from(currentNames)..removeAt(targetIndex);
        final newNicknames = List<String>.from(currentData['nicknames'] ?? [])..removeAt(targetIndex);
        final newReasons = List<String>.from(currentData['reasons'] ?? [])..removeAt(targetIndex);
        final newStatuses = List<String>.from(currentData['statuses'] ?? [])..removeAt(targetIndex);
        final newStaffIds = List<String>.from(currentData['staffIds'] ?? [])..removeAt(targetIndex);
        final newAlHours = List<double>.from((currentData['alHours'] as List? ?? []).map((e) => (e as num).toDouble()))..removeAt(targetIndex);
        final newClHours = List<double>.from((currentData['clHours'] as List? ?? []).map((e) => (e as num).toDouble()))..removeAt(targetIndex);
        final newSlHours = List<double>.from((currentData['slHours'] as List? ?? []).map((e) => (e as num).toDouble()))..removeAt(targetIndex);
        final newCompHours = List<double>.from((currentData['compHours'] as List? ?? []).map((e) => (e as num).toDouble()))..removeAt(targetIndex);

        final bool hasApproved = newStatuses.contains('approved');
        final bool hasPending = newStatuses.contains('pending');
        String overallStatus = 'pending';
        if (hasApproved && !hasPending) overallStatus = 'approved';
        else if (hasApproved && hasPending) overallStatus = 'partial';

        if (newNames.isEmpty) {
          transaction.delete(docRef);
        } else {
          transaction.update(docRef, {
            'names': newNames,
            'nicknames': newNicknames,
            'reasons': newReasons,
            'statuses': newStatuses,
            'staffIds': newStaffIds,
            'alHours': newAlHours,
            'clHours': newClHours,
            'slHours': newSlHours,
            'compHours': newCompHours,
            'status': overallStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      // 退還配額
      if (staffId.isNotEmpty) {
        if (alHours > 0) {
          await QuotaService.addLeave(staffId: staffId, leaveType: 'al', days: alHours / 8.0, reason: '管理員刪除請假');
        }
        if (clHours > 0) {
          await QuotaService.addLeave(staffId: staffId, leaveType: 'cl', days: clHours / 8.0, reason: '管理員刪除請假');
        }
        if (slHours > 0) {
          await QuotaService.addLeave(staffId: staffId, leaveType: 'sl', days: slHours / 8.0, reason: '管理員刪除請假');
        }
        if (compHours > 0) {
          await QuotaService.addCompTime(staffId: staffId, hours: compHours, reason: '管理員刪除請假退補鐘');
        }
      }

      onRefresh();
      return true;
    } catch (e) {
      debugPrint('adminForceDelete error: $e');
      return false;
    }
  }
}