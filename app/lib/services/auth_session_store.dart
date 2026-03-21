import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class AuthSessionStore {
  static const _sessionUserKey = 'expense_tracker_session_user';

  Future<void> saveUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionUserKey,
      jsonEncode({
        'id': user.id,
        'full_name': user.fullName,
        'phone': user.phone,
      }),
    );
  }

  Future<AppUser?> readUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionUserKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      return AppUser.fromJson(parsed);
    } catch (_) {
      await prefs.remove(_sessionUserKey);
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionUserKey);
  }
}
