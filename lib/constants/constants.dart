// lib/constants/constants.dart
import 'package:flutter/material.dart';

// SharedPreferences keys
const String SPK_MY_NAME = 'my_name';
const String SPK_NICKNAME = 'nickname';
const String SPK_STAFF_ID = 'staff_id';
const String SPK_JOB_TITLE = 'job_title';
const String SPK_GROUP = 'group';
const String SPK_LOGIN_GROUP = 'login_group';
const String SPK_PERMISSION_CODE = 'permission_code';
const String SPK_WORK_ALARM_ENABLED = 'work_alarm_enabled';
const String SPK_LOGIN_TIMESTAMP = 'login_timestamp';
const String SPK_SHIFT_CYCLE_START = 'shift_cycle_start';
const String SPK_SHIFT_CYCLE_LENGTH = 'shift_cycle_length';
const String SPK_PUBLIC_HOLIDAYS_JSON = 'public_holidays_json';
const String SPK_CUSTOM_HOLIDAYS_JSON = 'custom_holidays_json';
const String SPK_GOOGLE_SHEETS_API_KEY = 'google_sheets_api_key';

// Permission codes
const String PERMISSION_CODE_SUPER_ADMIN = 'SM';
const String PERMISSION_CODE_TEAM_LEAD = 'SR';

// Firestore collections
const String FIRESTORE_A_TEAM_LEAVE = 'a_team_leave';
const String FIRESTORE_B_TEAM_LEAVE = 'b_team_leave';
const String FIRESTORE_C_TEAM_LEAVE = 'c_team_leave';
const String FIRESTORE_D_TEAM_LEAVE = 'd_team_leave';

const Map<String, String> FIRESTORE_LEAVE_COLLECTIONS = {
  'A': FIRESTORE_A_TEAM_LEAVE,
  'B': FIRESTORE_B_TEAM_LEAVE,
  'C': FIRESTORE_C_TEAM_LEAVE,
  'D': FIRESTORE_D_TEAM_LEAVE,
};

// Leave types
const String LEAVE_TYPE_AL = 'AL';
const String LEAVE_TYPE_CL = 'CL';
const String LEAVE_TYPE_SL = 'SL';
const String LEAVE_TYPE_TR = 'TR';

const Map<String, String> LEAVE_TYPE_DISPLAY = {
  LEAVE_TYPE_AL: '年假',
  LEAVE_TYPE_CL: '公司假',
  LEAVE_TYPE_SL: '病假',
  LEAVE_TYPE_TR: 'TR',
};

// Shifts
const String SHIFT_M = 'M';
const String SHIFT_LM = 'LM';
const String SHIFT_A = 'A';
const String SHIFT_N = 'N';
const String SHIFT_LN = 'LN';
const String SHIFT_REST = 'REST';

const Map<String, String> SHIFT_DISPLAY = {
  SHIFT_M: '早班',
  SHIFT_LM: 'L早班',
  SHIFT_A: '中班',
  SHIFT_N: '夜班',
  SHIFT_LN: 'L夜班',
  SHIFT_REST: '休息',
};

const Map<String, String> SHIFT_TIME = {
  SHIFT_M: '08:00-16:00',
  SHIFT_LM: '08:00-20:00',
  SHIFT_A: '16:00-23:00',
  SHIFT_N: '23:00-08:00',
  SHIFT_LN: '20:00-08:00',
  SHIFT_REST: '休息',
};

const Map<String, int> SHIFT_START_HOURS = {
  SHIFT_M: 8,
  SHIFT_LM: 8,
  SHIFT_A: 16,
  SHIFT_N: 23,
  SHIFT_LN: 20,
  SHIFT_REST: 0,
};

// Colors
const Color COLOR_SHIFT_M = Color(0xFF1E88E5);
const Color COLOR_SHIFT_LM = Color(0xFF43A047);
const Color COLOR_SHIFT_A = Color(0xFFFB8C00);
const Color COLOR_SHIFT_N = Color(0xFF7B1FA2);
const Color COLOR_SHIFT_LN = Color(0xFF00838F);
const Color COLOR_SHIFT_REST = Color(0xFFBDBDBD);
const Color COLOR_HOLIDAY = Color(0xFFE53935);
const Color COLOR_CUSTOM_HOLIDAY = Color(0xFFFFA726);
const Color COLOR_ON_LEAVE = Color(0xFF43A047);

const Map<String, Color> SHIFT_COLORS = {
  SHIFT_M: COLOR_SHIFT_M,
  SHIFT_LM: COLOR_SHIFT_LM,
  SHIFT_A: COLOR_SHIFT_A,
  SHIFT_N: COLOR_SHIFT_N,
  SHIFT_LN: COLOR_SHIFT_LN,
  SHIFT_REST: COLOR_SHIFT_REST,
};

// Others
const int DEFAULT_SHIFT_CYCLE_LENGTH = 28;
const int SESSION_TIMEOUT_MINUTES = 30;
const List<String> TEAMS = ['A', 'B', 'C', 'D'];
const String CYCLE_START_DATE = '2025-12-13';

const Map<String, List<String>> TEAM_CYCLES = {
  'A': ['', '', 'M', 'M', 'A', 'A', 'N', 'LN', 'LN', '', '', 'M', 'M', 'A', '', '', 'N', 'N', '', '', 'M', 'LM', 'LM', 'A', 'A', 'N', 'N', ''],
  'B': ['LM', 'LM', 'A', 'A', 'N', 'N', '', '', '', 'M', 'M', 'A', 'A', 'N', 'LN', 'LN', '', '', 'M', 'M', 'A', '', '', 'N', 'N', '', '', 'M'],
  'C': ['', '', 'N', 'N', '', '', 'M', 'LM', 'LM', 'A', 'A', 'N', 'N', '', '', '', 'M', 'M', 'A', 'A', 'N', 'LN', 'LN', '', '', 'M', 'M', 'A'],
  'D': ['LN', 'LN', '', '', 'M', 'M', 'A', '', '', 'N', 'N', '', '', 'M', 'LM', 'LM', 'A', 'A', 'N', 'N', '', '', '', 'M', 'M', 'A', 'A', 'N'],
};

// Apps Script URLs
const String APPS_SCRIPT_URL_A_TEAM = 'https://script.google.com/macros/s/AKfycbygcFMluPzyScBZ-KjflhcHdXkzN02b-rwx7PSfpEI1ztRiIxh4XWe6uoit6tq6MZy3Vg/exec';
const String APPS_SCRIPT_URL_B_TEAM = 'https://script.google.com/macros/s/AKfycbzBsnwF_XwUtwgUzQDSLu7AgLbHOe0PtgtbTPQm2uYSSSLRF7QtwAPvhnBj61oTlWCa/exec';
const String APPS_SCRIPT_URL_C_TEAM = 'https://script.google.com/macros/s/AKfycbxghqBmz9dlGAaj5mw1_xNm5IaeBr8eeww0bqFYFHKs15HwcXbhq6hZkTxTR6TiiokUig/exec';
const String APPS_SCRIPT_URL_D_TEAM = 'https://script.google.com/macros/s/AKfycbz_UljpGPFvkvboykcR5mBMOy-Pf7uo9hkTFfnstBi8kNKLZGdIgMS0DdEEKQcdEPzWxg/exec';

const Map<String, String> APPS_SCRIPT_URLS = {
  'A': APPS_SCRIPT_URL_A_TEAM,
  'B': APPS_SCRIPT_URL_B_TEAM,
  'C': APPS_SCRIPT_URL_C_TEAM,
  'D': APPS_SCRIPT_URL_D_TEAM,
};

// 路由常數
const String ROUTE_LOGIN = '/login';
const String ROUTE_TEAM_MENU = '/teamMenu';
const String ROUTE_APPROVAL = '/approval';
const String ROUTE_MY_LEAVE = '/myLeave';
const String ROUTE_CANCEL_LEAVE = '/cancelLeave';
const String ROUTE_DESKTOP_WIDGETS = '/desktopWidgets';
const String ROUTE_HOLIDAYS = '/holidays';
const String ROUTE_WHATSAPP_CONFIG = '/whatsappConfig';
const String ROUTE_GOOGLE_SHEETS_CONFIG = '/googleSheetsConfig';
const String ROUTE_CALENDAR_A = '/calendarA';
const String ROUTE_CALENDAR_B = '/calendarB';
const String ROUTE_CALENDAR_C = '/calendarC';
const String ROUTE_CALENDAR_D = '/calendarD';

// 公告路由
const String ROUTE_NOTIFICATIONS = '/notifications';
const String ROUTE_ADMIN_NOTIFICATIONS = '/admin_notifications';