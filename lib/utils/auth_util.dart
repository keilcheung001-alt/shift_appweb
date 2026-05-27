import 'package:shared_preferences/shared_preferences.dart';
import '../constants/constants.dart';

class AuthUtil {
  static const String _keyLastActive = 'last_active_time';
  static const int _sessionTimeoutMinutes = 30;

  static Future<bool> canEditTeamCalendar(String team) async {
    final canFullEdit = await getCanFullEdit();
    if (canFullEdit) return true;
    final myTeam = await getHomeGroup();
    return team.toUpperCase() == myTeam.toUpperCase();
  }

  static Future<bool> getCanFullEdit() async {
    final prefs = await SharedPreferences.getInstance();
    final code = (prefs.getString(SPK_PERMISSION_CODE) ?? '').trim().toUpperCase();
    return code == PERMISSION_CODE_SUPER_ADMIN || code == PERMISSION_CODE_TEAM_LEAD;
  }

  static Future<bool> getIsSuperAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final code = (prefs.getString(SPK_PERMISSION_CODE) ?? '').trim().toUpperCase();
    return code == PERMISSION_CODE_SUPER_ADMIN;
  }

  static Future<bool> getIsTeamLead() async {
    final prefs = await SharedPreferences.getInstance();
    final code = (prefs.getString(SPK_PERMISSION_CODE) ?? '').trim().toUpperCase();
    return code == PERMISSION_CODE_TEAM_LEAD;
  }

  static Future<String> getHomeGroup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SPK_GROUP) ?? 'A';
  }

  static Future<String> getLoginGroup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SPK_LOGIN_GROUP) ?? 'A';
  }

  static Future<String> getStaffId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SPK_STAFF_ID) ?? '';
  }

  static Future<String> getMyName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SPK_MY_NAME) ?? '';
  }

  static Future<String> getNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SPK_NICKNAME) ?? '';
  }

  static Future<String> getJobTitle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SPK_JOB_TITLE) ?? '';
  }

  static Future<String> getPermissionCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SPK_PERMISSION_CODE) ?? '';
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(SPK_LOGIN_TIMESTAMP);
    if (timestamp == null) return false;
    final loginTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    return now.difference(loginTime).inMinutes < SESSION_TIMEOUT_MINUTES;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SPK_LOGIN_TIMESTAMP);
    await prefs.remove(_keyLastActive);
  }

  static Future<void> updateLoginTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SPK_LOGIN_TIMESTAMP, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<int> getLoginMinutesAgo() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(SPK_LOGIN_TIMESTAMP);
    if (timestamp == null) return -1;
    final loginTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    return now.difference(loginTime).inMinutes;
  }

  static Future<void> updateLastActiveTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastActive, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> isSessionExpired() async {
    // 取消自動登出
    return false;
  }
}