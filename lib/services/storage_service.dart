import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger.dart';

/// Persistance minimale : settings + token d'auth WiFi.
/// Le contenu du prompteur n'est plus persisté (poussé via WS à chaque session).
class StorageService {
  static const _keySettings = 'settings_json';
  static const _keyAuthToken = 'auth_token';

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get _p async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Settings

  static Future<Map<String, dynamic>> loadSettings() async {
    final p = await _p;
    final raw = p.getString(_keySettings);
    if (raw == null) return const {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e, st) {
      Log.e('Storage', 'failed to parse settings', e, st);
      return const {};
    }
  }

  static Future<void> saveSettings(Map<String, dynamic> json) async {
    try {
      final p = await _p;
      await p.setString(_keySettings, jsonEncode(json));
    } catch (e, st) {
      Log.e('Storage', 'failed to save settings', e, st);
    }
  }

  // ── Auth token (pour la télécommande PC)

  static Future<String> getOrCreateAuthToken() async {
    final p = await _p;
    var token = p.getString(_keyAuthToken);
    if (token == null || token.length != 6) {
      // 6 chiffres
      final rng = DateTime.now().millisecondsSinceEpoch;
      token = ((rng % 900000) + 100000).toString();
      await p.setString(_keyAuthToken, token);
    }
    return token;
  }

  static Future<void> regenAuthToken() async {
    final p = await _p;
    await p.remove(_keyAuthToken);
  }
}
