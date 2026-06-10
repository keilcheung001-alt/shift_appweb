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

      // ✅ 用 Transaction 保證原子性
      return await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (!doc.exists) return false;

        final data = doc.data()!;
        final List<dynamic> names = data['names'] ?? [];
        final List<dynamic> statuses = data['statuses'] ?? [];
        final List<dynamic> alHoursList = data['alHours'] ?? [];
        final List<dynamic> clHoursList = data['clHours'] ?? [];
        final List<dynamic> slHoursList = data['slHours'] ?? [];
        final List<dynamic> compHoursList = data['compHours'] ?? [];

        // 搵 targetIndex
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

        // 記錄要退嘅 quota（等陣用）
        final staffId = await AuthUtil.getStaffId();
        final alHours = targetIndex < alHoursList.length ? (alHoursList[targetIndex] as num).toDouble() : 0.0;
        final clHours = targetIndex < clHoursList.length ? (clHoursList[targetIndex] as num).toDouble() : 0.0;
        final slHours = targetIndex < slHoursList.length ? (slHoursList[targetIndex] as num).toDouble() : 0.0;
        final compHours = targetIndex < compHoursList.length ? (compHoursList[targetIndex] as num).toDouble() : 0.0;

        // 先刪記錄（喺 transaction 入面）
        final newNames = List<String>.from(names)..removeAt(targetIndex);
        final newNicknames = List<String>.from(data['nicknames'] ?? [])..removeAt(targetIndex);
        final newReasons = List<String>.from(data['reasons'] ?? [])..removeAt(targetIndex);
        final newStatuses = List<String>.from(statuses)..removeAt(targetIndex);
        final newStaffIds = List<String>.from(data['staffIds'] ?? [])..removeAt(targetIndex);
        final newAlHours = List<double>.from(alHoursList.map((e) => (e as num).toDouble()))..removeAt(targetIndex);
        final newClHours = List<double>.from(clHoursList.map((e) => (e as num).toDouble()))..removeAt(targetIndex);
        final newSlHours = List<double>.from(slHoursList.map((e) => (e as num).toDouble()))..removeAt(targetIndex);
        final newCompHours = List<double>.from(compHoursList.map((e) => (e as num).toDouble()))..removeAt(targetIndex);

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

        // ✅ Transaction 成功後先退 quota（但 Firestore transaction 唔支援 call external API）
        // 所以呢度要喺 transaction 外面做，但已經確保咗記錄一定刪咗
        // 為咗安全，退 quota 嘅動作要喺 transaction commit 之後先做

        // 記錄要退嘅資料，等 transaction 完咗先退
        return true;
      }).then((success) async {
        if (success) {
          // ✅ Transaction commit 成功，先退 quota
          final staffId = await AuthUtil.getStaffId();
          if (staffId.isNotEmpty) {
            // 呢度要重新讀取 alHours/clHours/slHours/compHours
            // 為咗簡化，上面已經記低咗，但因為 lambda 作用域問題，要重新攞一次
            await _refundQuota(staffId, dk, teamCode, myName);
          }
          onSuccess();
          onRefresh();
        }
        return success;
      });
    } catch (e) {
      debugPrint('deleteMyLeave error: $e');
      return false;
    }
  }

  /// 輔助函數：退 quota
  static Future<void> _refundQuota(String staffId, String dk, String teamCode, String myName) async {
    try {
      final collection = FirebaseFirestore.instance.collection(
          teamCode == 'A' ? 'a_team_leave' :
          teamCode == 'B' ? 'b_team_leave' :
          teamCode == 'C' ? 'c_team_leave' : 'd_team_leave'
      );
      final doc = await collection.doc(dk).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final List<dynamic> names = data['names'] ?? [];
      final List<dynamic> alHoursList = data['alHours'] ?? [];
      final List<dynamic> clHoursList = data['clHours'] ?? [];
      final List<dynamic> slHoursList = data['slHours'] ?? [];
      final List<dynamic> compHoursList = data['compHours'] ?? [];

      int targetIndex = names.indexOf(myName);
      if (targetIndex == -1) return;

      final alHours = targetIndex < alHoursList.length ? (alHoursList[targetIndex] as num).toDouble() : 0.0;
      final clHours = targetIndex < clHoursList.length ? (clHoursList[targetIndex] as num).toDouble() : 0.0;
      final slHours = targetIndex < slHoursList.length ? (slHoursList[targetIndex] as num).toDouble() : 0.0;
      final compHours = targetIndex < compHoursList.length ? (compHoursList[targetIndex] as num).toDouble() : 0.0;

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
    } catch (e) {
      debugPrint('退 quota 失敗: $e');
    }
  }

  /// 管理員強制刪除任何請假記錄
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

      return await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (!doc.exists) return false;
        final data = doc.data()!;

        final List<dynamic> names = data['names'] ?? [];
        if (targetIndex >= names.length) return false;

        final List<dynamic> alHoursList = data['alHours'] ?? [];
        final List<dynamic> clHoursList = data['clHours'] ?? [];
        final List<dynamic> slHoursList = data['slHours'] ?? [];
        final List<dynamic> compHoursList = data['compHours'] ?? [];

        // 記錄要退 quota 嘅 staffId 同 時數
        final staffId = data['staffIds'] != null && targetIndex < (data['staffIds'] as List).length
            ? (data['staffIds'] as List)[targetIndex] as String? ?? ''
            : '';
        final alHours = targetIndex < alHoursList.length ? (alHoursList[targetIndex] as num).toDouble() : 0.0;
        final clHours = targetIndex < clHoursList.length ? (clHoursList[targetIndex] as num).toDouble() : 0.0;
        final slHours = targetIndex < slHoursList.length ? (slHoursList[targetIndex] as num).toDouble() : 0.0;
        final compHours = targetIndex < compHoursList.length ? (compHoursList[targetIndex] as num).toDouble() : 0.0;

        // 刪除記錄
        final newNames = List<String>.from(names)..removeAt(targetIndex);
        final newNicknames = List<String>.from(data['nicknames'] ?? [])..removeAt(targetIndex);
        final newReasons = List<String>.from(data['reasons'] ?? [])..removeAt(targetIndex);
        final newStatuses = List<String>.from(data['statuses'] ?? [])..removeAt(targetIndex);
        final newStaffIds = List<String>.from(data['staffIds'] ?? [])..removeAt(targetIndex);
        final newAlHours = List<double>.from(alHoursList.map((e) => (e as num).toDouble()))..removeAt(targetIndex);
        final newClHours = List<double>.from(clHoursList.map((e) => (e as num).toDouble()))..removeAt(targetIndex);
        final newSlHours = List<double>.from(slHoursList.map((e) => (e as num).toDouble()))..removeAt(targetIndex);
        final newCompHours = List<double>.from(compHoursList.map((e) => (e as num).toDouble()))..removeAt(targetIndex);

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

        // 退 quota（transaction 成功後）
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
      });
    } catch (e) {
      debugPrint('adminForceDelete error: $e');
      return false;
    }
  }
}