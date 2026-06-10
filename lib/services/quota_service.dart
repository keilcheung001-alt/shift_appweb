// lib/services/quota_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class QuotaService {
  static const String collectionName = 'user_quotas';

  // 🔥 強制轉型 helper，解決類型不匹配問題
  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static Future<Map<String, dynamic>> getOrCreateQuota(
      String staffId, {
        String? name,
        String? team,
      }) async {
    try {
      final docRef = FirebaseFirestore.instance.collection(collectionName).doc(staffId);
      final doc = await docRef.get();

      if (doc.exists) {
        await _checkYearlyUpdate(staffId, doc.data()!);
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
        debugPrint('✅ 自動建立員工配額: $staffId ($name, $team)');
        return newQuota;
      }
    } catch (e) {
      debugPrint('獲取配額失敗: $e');
      return _getDefaultQuota();
    }
  }

  static Future<void> _checkYearlyUpdate(String staffId, Map<String, dynamic> currentData) async {
    final now = DateTime.now();
    final lastYear = currentData['lastUpdatedYear'] ?? now.year;
    final lastMonth = currentData['lastUpdatedMonth'] ?? now.month;

    final Map<String, dynamic> updates = {};

    if (now.year > lastYear && now.month == 1 && now.day == 1) {
      updates['al'] = _toDouble(currentData['al']) + 15.0;
      updates['cl'] = _toDouble(currentData['cl']) + 17.0;
      updates['lastUpdatedYear'] = now.year;
      debugPrint('📅 年度更新: $staffId  AL+15, CL+17');
    }

    if (now.year > lastYear || now.month > lastMonth) {
      final monthsPassed = (now.year - lastYear) * 12 + (now.month - lastMonth);
      if (monthsPassed > 0) {
        double currentSL = _toDouble(currentData['sl']);
        double newSL = currentSL + (monthsPassed * 4.0);
        if (newSL > 120.0) newSL = 120.0;
        updates['sl'] = newSL;
        updates['lastUpdatedMonth'] = now.month;
        if (now.year > lastYear) updates['lastUpdatedYear'] = now.year;
        debugPrint('📅 月度更新: $staffId  病假 +${monthsPassed * 4}');
      }
    }

    if (updates.isNotEmpty) {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance.collection(collectionName).doc(staffId).update(updates);
    }
  }

  static Map<String, dynamic> _getDefaultQuota() {
    return {
      'al': 10.0,
      'cl': 7.0,
      'sl': 10.0,
      'compTime': 0.0,
    };
  }

  static Future<double> getCompBalance(String staffId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection(collectionName).doc(staffId).get();
      if (doc.exists) {
        return _toDouble(doc.data()?['compTime']);
      }
      return 0.0;
    } catch (e) {
      debugPrint('獲取補鐘餘額失敗: $e');
      return 0.0;
    }
  }

  static Future<Map<String, dynamic>?> getCurrentQuota(String staffId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection(collectionName).doc(staffId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      debugPrint('獲取配額失敗: $e');
      return null;
    }
  }

  // ✅ 扣減假期：加入型別安全及錯誤打印
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
          final newValue = _toDouble(defaultQuota[leaveType]) - days;
          transaction.set(docRef, {
            'staffId': staffId,
            'al': leaveType == 'al' ? newValue : defaultQuota['al'],
            'cl': leaveType == 'cl' ? newValue : defaultQuota['cl'],
            'sl': leaveType == 'sl' ? newValue : defaultQuota['sl'],
            'compTime': 0.0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }
        final data = doc.data() as Map<String, dynamic>;
        final currentValue = _toDouble(data[leaveType]);
        final newValue = currentValue - days;
        if (newValue < 0) {
          throw Exception('Insufficient $leaveType balance: $currentValue < $days');
        }
        transaction.update(docRef, {
          leaveType: newValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      debugPrint('✅ 扣減假期: $staffId $leaveType -$days 日');
      return true;
    } catch (e) {
      debugPrint('❌ 扣減假期失敗: $e');
      return false;
    }
  }

  // ✅ 退回假期
  static Future<bool> addLeave({
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
          final newValue = _toDouble(defaultQuota[leaveType]) + days;
          transaction.set(docRef, {
            'staffId': staffId,
            'al': leaveType == 'al' ? newValue : defaultQuota['al'],
            'cl': leaveType == 'cl' ? newValue : defaultQuota['cl'],
            'sl': leaveType == 'sl' ? newValue : defaultQuota['sl'],
            'compTime': 0.0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }
        final data = doc.data() as Map<String, dynamic>;
        final currentValue = _toDouble(data[leaveType]);
        transaction.update(docRef, {
          leaveType: currentValue + days,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      debugPrint('✅ 退回假期: $staffId $leaveType +$days 日');
      return true;
    } catch (e) {
      debugPrint('退回假期失敗: $e');
      return false;
    }
  }

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
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }
        final data = doc.data() as Map<String, dynamic>;
        final currentComp = _toDouble(data['compTime']);
        transaction.update(docRef, {
          'compTime': currentComp + hours,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      debugPrint('✅ 增加補鐘: $staffId +$hours 小時');
      return true;
    } catch (e) {
      debugPrint('增加補鐘失敗: $e');
      return false;
    }
  }

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
            'compTime': -hours,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }
        final data = doc.data() as Map<String, dynamic>;
        final currentComp = _toDouble(data['compTime']);
        final newComp = currentComp - hours;
        if (newComp < 0) {
          throw Exception('Insufficient comp time balance');
        }
        transaction.update(docRef, {
          'compTime': newComp,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      debugPrint('✅ 扣減補鐘: $staffId -$hours 小時');
      return true;
    } catch (e) {
      debugPrint('扣減補鐘失敗: $e');
      return false;
    }
  }

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

      await FirebaseFirestore.instance.collection(collectionName).doc(staffId).update(updateData);
      return true;
    } catch (e) {
      debugPrint('更新配額失敗: $e');
      return false;
    }
  }

  static Stream<DocumentSnapshot> streamQuota(String staffId) {
    return FirebaseFirestore.instance.collection(collectionName).doc(staffId).snapshots();
  }
}
