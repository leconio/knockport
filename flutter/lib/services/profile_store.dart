import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/knock_profile.dart';

class ProfileStore {
  static const _profileKey = 'knockgate_profile_v1';
  static const _historyKey = 'knockgate_history_v1';

  Future<KnockProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null) {
      return KnockProfile.defaults();
    }
    try {
      return KnockProfile.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return KnockProfile.defaults();
    }
  }

  Future<void> saveProfile(KnockProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  Future<List<String>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyKey) ?? const <String>[];
  }

  Future<void> saveHistory(List<String> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, events.take(80).toList());
  }
}
