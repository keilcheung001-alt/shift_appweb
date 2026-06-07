// lib/services/compensatory_time_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class CompensatoryTimeService {
  static const String _keyPrefix = 'comp_time_';

  /// 獲取員工補鐘餘額（小時）
  static Future<double> getBalance(String staffId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('$_keyPrefix$staffId') ?? 0.0;
  }

  /// 設定員工補鐘餘額
  static Future<void> setBalance(String staffId, double hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_keyPrefix$staffId', hours);
  }

  /// 增加補鐘（OT 累積）
  static Future<void> addCompTime(String staffId, double hours) async {
    final current = await getBalance(staffId);
    await setBalance(staffId, current + hours);
  }

  /// 扣減補鐘（請假用）
  static Future<bool> deductCompTime(String staffId, double hours) async {
    final current = await getBalance(staffId);
    if (current >= hours) {
      await setBalance(staffId, current - hours);
      return true;
    } else {
      await setBalance(staffId, 0);
      return false;
    }
  }
}