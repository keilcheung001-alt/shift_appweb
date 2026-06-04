// lib/services/leave_delete_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/constants.dart';

class LeaveDeleteService {
  /// 員工自己刪除自己的 pending/rejected 記錄
  static Future<bool> deleteMyLeave({
    required String teamCode,
    required String myName,
    required DateTime day,
    required VoidCallback onSuccess,
    required VoidCallback onRefresh,
  }) async {
    if (myName.trim().isEmpty) {
      debugPrint('未設定姓名，無法取消請假');
      return false;
    }

    final collectionName = FIRESTORE_LEAVE_COLLECTIONS[teamCode]!;
    final dateKey = _dateKey(day);
    final docRef = FirebaseFirestore.instance.collection(collectionName).doc(dateKey);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;

        final data = snap.data()!;
        final names = List<String>.from(data['names']?.map((e) => e.toString().trim()) ?? []);
        final reasons = List<String>.from(data['reasons']?.map((e) => e.toString().trim()) ?? []);
        final statuses = List<String>.from(data['statuses']?.map((e) => e.toString().trim()) ?? []);
        final nicknames = List<String>.from(data['nicknames']?.map((e) => e.toString().trim()) ?? []);
        final staffIds = List<String>.from(data['staffIds']?.map((e) => e.toString().trim()) ?? []);

        final idx = names.indexWhere((n) => n.toLowerCase() == myName.trim().toLowerCase());
        if (idx == -1) return;

        // 只允許刪除 pending 或 rejected
        if (idx >= statuses.length) return;
        if (statuses[idx] != 'pending' && statuses[idx] != 'rejected') return;

        names.removeAt(idx);
        if (idx < reasons.length) reasons.removeAt(idx);
        if (idx < statuses.length) statuses.removeAt(idx);
        if (idx < nicknames.length) nicknames.removeAt(idx);
        if (idx < staffIds.length) staffIds.removeAt(idx);

        if (names.isEmpty) {
          tx.delete(docRef);
        } else {
          final hasApproved = statuses.contains('approved');
          final hasPending = statuses.contains('pending');
          String overallStatus = 'pending';
          if (hasApproved && !hasPending) {
            overallStatus = 'approved';
          } else if (hasApproved && hasPending) {
            overallStatus = 'partial';
          } else if (!hasApproved && !hasPending) {
            overallStatus = 'rejected';
          }

          tx.update(docRef, {
            'names': names,
            'reasons': reasons,
            'statuses': statuses,
            'nicknames': nicknames,
            'staffIds': staffIds,
            'status': overallStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      onRefresh();
      onSuccess();
      return true;
    } catch (e) {
      debugPrint('刪除失敗: $e');
      return false;
    }
  }

  /// Super Admin 強制刪除任何員工記錄
  static Future<bool> adminForceDelete({
    required String teamCode,
    required DateTime day,
    required int targetIndex,
    required VoidCallback onRefresh,
  }) async {
    final collectionName = FIRESTORE_LEAVE_COLLECTIONS[teamCode]!;
    final dateKey = _dateKey(day);
    final docRef = FirebaseFirestore.instance.collection(collectionName).doc(dateKey);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;

        final data = snap.data()!;
        final names = List<String>.from(data['names'] ?? []);
        final reasons = List<String>.from(data['reasons'] ?? []);
        final statuses = List<String>.from(data['statuses'] ?? []);
        final nicknames = List<String>.from(data['nicknames'] ?? []);
        final staffIds = List<String>.from(data['staffIds'] ?? []);

        if (targetIndex >= names.length) return;

        names.removeAt(targetIndex);
        if (targetIndex < reasons.length) reasons.removeAt(targetIndex);
        if (targetIndex < statuses.length) statuses.removeAt(targetIndex);
        if (targetIndex < nicknames.length) nicknames.removeAt(targetIndex);
        if (targetIndex < staffIds.length) staffIds.removeAt(targetIndex);

        if (names.isEmpty) {
          tx.delete(docRef);
        } else {
          final hasApproved = statuses.contains('approved');
          final hasPending = statuses.contains('pending');
          String overallStatus = 'pending';
          if (hasApproved && !hasPending) {
            overallStatus = 'approved';
          } else if (hasApproved && hasPending) {
            overallStatus = 'partial';
          } else if (!hasApproved && !hasPending) {
            overallStatus = 'rejected';
          }

          tx.update(docRef, {
            'names': names,
            'reasons': reasons,
            'statuses': statuses,
            'nicknames': nicknames,
            'staffIds': staffIds,
            'status': overallStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      onRefresh();
      return true;
    } catch (e) {
      debugPrint('Admin 強制刪除失敗: $e');
      return false;
    }
  }

  /// 獲取某一天的所有請假員工（連狀態）
  static List<Map<String, dynamic>> getLeavePeopleForDay(
      Map<String, Map<String, dynamic>> teamLeave,
      DateTime day,
      ) {
    final dateKey = _dateKey(day);
    final info = teamLeave[dateKey];
    if (info == null) return [];

    final names = (info['names'] as List<dynamic>?)?.cast<String>() ?? [];
    final statuses = (info['statuses'] as List<dynamic>?)?.cast<String>() ?? [];
    final nicknames = (info['nicknames'] as List<dynamic>?)?.cast<String>() ?? [];

    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < names.length; i++) {
      result.add({
        'index': i,
        'name': names[i],
        'nickname': i < nicknames.length ? nicknames[i] : '',
        'status': i < statuses.length ? statuses[i] : 'pending',
      });
    }
    return result;
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}