import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WhatsAppGroups {
  static const Map<String, String> _defaultGroupLinks = {
    'A': 'https://chat.whatsapp.com/HEkaCeylrtZK68Yifrb3bC',
    'B': 'https://chat.whatsapp.com/JXtZbQSFlHqDvnxRXqSCVA',
    'C': 'https://chat.whatsapp.com/IPmD0YM0gx7HUQsFYg8jE3',
    'D': 'https://chat.whatsapp.com/ILPF2ALBGb11kaUhCwvHmP',
  };

  static String _key(String teamCode) => 'whatsapplink${teamCode.toUpperCase()}';

  static Future<String?> getLinkForTeam(String teamCode) async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_key(teamCode));
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim();
    }
    return _defaultGroupLinks[teamCode.toUpperCase()];
  }

  static Future<Map<String, String>> getAllLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, String> links = {};
    for (final team in ['A', 'B', 'C', 'D']) {
      final custom = prefs.getString(_key(team));
      links[team] = custom?.trim().isNotEmpty == true
          ? custom!.trim()
          : _defaultGroupLinks[team]!;
    }
    return links;
  }

  static Future<void> setCustomLink(String teamCode, String link) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(teamCode), link.trim());
  }

  static Future<void> clearCustomLink(String teamCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(teamCode));
  }
}