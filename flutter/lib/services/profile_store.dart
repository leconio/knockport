import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/knock_profile.dart';

class ProfileStore {
  static const _profileKey = 'knockgate_profile_v1';
  static const _autoRefreshEnabledKey = 'knockgate_auto_refresh_enabled_v1';
  static const _lastPublicIPKey = 'knockgate_auto_last_public_ip_v1';
  static const _lastKnockUnixKey = 'knockgate_auto_last_knock_unix_v1';

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

  Future<bool> loadAutoRefreshEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoRefreshEnabledKey) ?? false;
  }

  Future<void> saveAutoRefreshEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoRefreshEnabledKey, enabled);
  }

  Future<AutoRefreshState> loadAutoRefreshState() async {
    final prefs = await SharedPreferences.getInstance();
    final unix = prefs.getInt(_lastKnockUnixKey);
    return AutoRefreshState(
      lastPublicIP: prefs.getString(_lastPublicIPKey),
      lastKnock: unix == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(unix * 1000),
    );
  }

  Future<void> saveAutoRefreshState({
    required String publicIP,
    required DateTime lastKnock,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPublicIPKey, publicIP);
    await prefs.setInt(
      _lastKnockUnixKey,
      lastKnock.millisecondsSinceEpoch ~/ 1000,
    );
  }

  Future<void> clearAutoRefreshState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastPublicIPKey);
    await prefs.remove(_lastKnockUnixKey);
  }
}

class AutoRefreshState {
  const AutoRefreshState({this.lastPublicIP, this.lastKnock});

  final String? lastPublicIP;
  final DateTime? lastKnock;
}
