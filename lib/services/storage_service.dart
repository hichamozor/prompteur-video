import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/script_model.dart';
import 'logger.dart';

class StorageService {
  static const _keySettings = 'settings_json';
  static const _keyDraft = 'editor_draft';
  static const _keyLastOpenedScriptId = 'last_opened_script_id';

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

  // ── Scripts library

  static Future<File> _scriptsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/scripts.json');
  }

  static Future<List<Script>> loadScripts() async {
    try {
      final f = await _scriptsFile();
      if (!await f.exists()) return [];
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Script.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      Log.e('Storage', 'failed to load scripts', e, st);
      return [];
    }
  }

  static Future<void> saveScripts(List<Script> scripts) async {
    try {
      final f = await _scriptsFile();
      final list = scripts.map((s) => s.toJson()).toList();
      await f.writeAsString(jsonEncode(list));
    } catch (e, st) {
      Log.e('Storage', 'failed to save scripts', e, st);
    }
  }

  // ── Editor draft (work-in-progress sans script associé)

  static Future<String?> loadDraft() async {
    final p = await _p;
    return p.getString(_keyDraft);
  }

  static Future<void> saveDraft(String text) async {
    final p = await _p;
    await p.setString(_keyDraft, text);
  }

  static Future<void> clearDraft() async {
    final p = await _p;
    await p.remove(_keyDraft);
  }

  // ── Last opened script

  static Future<String?> getLastOpenedScriptId() async {
    final p = await _p;
    return p.getString(_keyLastOpenedScriptId);
  }

  static Future<void> setLastOpenedScriptId(String? id) async {
    final p = await _p;
    if (id == null) {
      await p.remove(_keyLastOpenedScriptId);
    } else {
      await p.setString(_keyLastOpenedScriptId, id);
    }
  }
}
