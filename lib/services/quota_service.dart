// lib/services/quota_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuotaService {
  static const String collectionName = 'user_quotas';

  /// 獲取或自動建立員工配額（包含姓名和隊伍）
  static Future<Map<String, dynamic>> getOrCreateQuota(
      String staffId, {
        String? name,
        String? team,
      }) async {
    try {
      final docRef = FirebaseFirestore.instance.collection(collectionName).doc(staffId);
      final doc = await docRef.get();

      if (doc.exists) {
        // 有記錄，檢查是否需要年度更新
        await _checkYearlyUpdate(staffId, doc.data()!);
        // 如果有新嘅姓名/隊伍，順便更新
        final currentData = doc.data()!;
        final Map<String, dynamic> updates = {};
        if (name != null && name.isNotEmpty && currentData['name'] != name) {
          updates['name'] = name;
        }
        if (team != null && team.isNotEmpty && currentData['team'] != team) {
          updates['team'] = team;
        }
        if (updates.isNotEmpty) {
          updates['updatedAt'] = FieldValue.serverTimestamp();
          await docRef.update(updates);
        }
        final updatedDoc = await docRef.get();
        return updatedDoc.data()!;
      } else {
        // 冇記錄就自動建立（用預設值）
        final defaultQuota = _getDefaultQuota();

        final now = DateTime.now();
        final newQuota = {
          'staffId': staffId,
          'name': name ?? staffId,
          'team': team ?? 'A',
          'al': defaultQuota['al'],
          'cl': defaultQuota['cl'],
          'sl': defaultQuota['sl'],
          'compTime': 0.0,
          'year': now.year,
          'lastUpdatedYear': now.year,
          'lastUpdatedMonth': now.month,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'isAutoCreated': true,
        };

        await docRef.set(newQuota);
        debugPrint('✅ 自動建立員工配額: $staffId ($name, $team) | AL=${defaultQuota['al']}, CL=${defaultQuota['cl']}, SL=${defaultQuota['sl']}');

        return newQuota;
      }
    } catch (e) {
      debugPrint('獲取配額失敗: $e');
      return _getDefaultQuota();
    }
  }

  /// 檢查並執行年度/月度更新
  static Future<void> _checkYearlyUpdate(String staffId, Map<String, dynamic> currentData) async {
    final now = DateTime.now();
    final lastYear = currentData['lastUpdatedYear'] ?? now.year;
    final lastMonth = currentData['lastUpdatedMonth'] ?? now.month;

    final Map<String, dynamic> updates = {};

    // 年度更新（每年1月1日）
    if (now.year > lastYear && now.month == 1 && now.day == 1) {
      updates['al'] = (currentData['al'] as num?)?.toDouble() ?? 0.0 + 15.0;
      updates['cl'] = (currentData['cl'] as num?)?.toDouble() ?? 0.0 + 17.0;
      updates['lastUpdatedYear'] = now.year;
      debugPrint('📅 年度更新: $staffId  AL+15, CL+17');
    }

    // 月度更新（病假每月+4，上限120）
    if (now.year > lastYear || now.month > lastMonth) {
      final monthsPassed = (now.year - lastYear) * 12 + (now.month - lastMonth);
      if (monthsPassed > 0) {
        double currentSL = (currentData['sl'] as num?)?.toDouble() ?? 0.0;
        double newSL = currentSL + (monthsPassed * 4.0);
        if (newSL > 120.0) newSL = 120.0;
        updates['sl'] = newSL;
        updates['lastUpdatedMonth'] = now.month;
        if (now.year > lastYear) updates['lastUpdatedYear'] = now.year;
        debugPrint('📅 月度更新: $staffId  病假 +${monthsPassed * 4} (現為 $newSL)');
      }
    }

    // 執行更新
    if (updates.isNotEmpty) {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(staffId)
          .update(updates);
    }
  }

  /// 獲取預設配額
  static Map<String, dynamic> _getDefaultQuota() {
    return {
      'al': 10.0,
      'cl': 7.0,
      'sl': 10.0,
      'compTime': 0.0,
    };
  }

  /// 檢查假期係咪足夠（測試階段全部夠）
  static Future<bool> hasEnoughLeave({
    required String staffId,
    required String leaveType,
    required double daysNeeded,
  }) async {
    return true;
  }

  /// 扣減假期
  static Future<bool> deductLeave({
    required String staffId,
    required String leaveType,
    required double days,
    required String reason,
  }) async {
    try {
      final docRef = FirebaseFirestore.instance.collection(collectionName).doc(staffId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          final defaultQuota = _getDefaultQuota();
          final newQuota = {
            'staffId': staffId,
            'al': defaultQuota['al'],
            'cl': defaultQuota['cl'],
            'sl': defaultQuota['sl'],
            'compTime': 0.0,
            'year': DateTime.now().year,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          transaction.set(docRef, newQuota);

          final newValue = (defaultQuota[leaveType] as num).toDouble() - days;
          transaction.update(docRef, {
            leaveType: newValue,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final current = doc.data()!;
          final currentValue = (current[leaveType] as num?)?.toDouble() ?? 0.0;
          final newValue = currentValue - days;

          transaction.update(docRef, {
            leaveType: newValue,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      debugPrint('✅ 扣減假期: $staffId $leaveType -$days');
      return true;
    } catch (e) {
      debugPrint('扣減假期失敗: $e，但繼續處理請假');
      return true;
    }
  }

  /// 扣減補鐘
  static Future<bool> deductCompTime({
    required String staffId,
    required double hours,
  }) async {
    try {
      final docRef = FirebaseFirestore.instance.collection(collectionName).doc(staffId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          final defaultQuota = _getDefaultQuota();
          transaction.set(docRef, {
            'staffId': staffId,
            'al': defaultQuota['al'],
            'cl': defaultQuota['cl'],
            'sl': defaultQuota['sl'],
            'compTime': 0.0 - hours,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final current = doc.data()!;
          final currentComp = (current['compTime'] as num?)?.toDouble() ?? 0.0;
          transaction.update(docRef, {
            'compTime': currentComp - hours,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      return true;
    } catch (e) {
      debugPrint('扣減補鐘失敗: $e');
      return true;
    }
  }

  /// 增加補鐘
  static Future<bool> addCompTime({
    required String staffId,
    required double hours,
    required String reason,
  }) async {
    try {
      final docRef = FirebaseFirestore.instance.collection(collectionName).doc(staffId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          final defaultQuota = _getDefaultQuota();
          transaction.set(docRef, {
            'staffId': staffId,
            'al': defaultQuota['al'],
            'cl': defaultQuota['cl'],
            'sl': defaultQuota['sl'],
            'compTime': hours,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final current = doc.data()!;
          final currentComp = (current['compTime'] as num?)?.toDouble() ?? 0.0;
          transaction.update(docRef, {
            'compTime': currentComp + hours,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      return true;
    } catch (e) {
      debugPrint('增加補鐘失敗: $e');
      return false;
    }
  }

  /// 獲取員工配額（Stream，實時更新）
  static Stream<DocumentSnapshot> streamQuota(String staffId) {
    return FirebaseFirestore.instance
        .collection(collectionName)
        .doc(staffId)
        .snapshots();
  }

  /// 管理員更新配額
  static Future<bool> updateQuota({
    required String staffId,
    double? al,
    double? cl,
    double? sl,
    double? compTime,
    required String updatedBy,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      };
      if (al != null) updateData['al'] = al;
      if (cl != null) updateData['cl'] = cl;
      if (sl != null) updateData['sl'] = sl;
      if (compTime != null) updateData['compTime'] = compTime;

      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(staffId)
          .update(updateData);

      return true;
    } catch (e) {
      debugPrint('更新配額失敗: $e');
      return false;
    }
  }

  /// 獲取員工當前配額
  static Future<Map<String, dynamic>?> getCurrentQuota(String staffId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(staffId)
          .get();

      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      debugPrint('獲取配額失敗: $e');
      return null;
    }
  }
}