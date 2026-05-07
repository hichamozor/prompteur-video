import 'package:flutter/material.dart';
import '../models/script_model.dart';
import '../services/logger.dart';
import '../services/storage_service.dart';

class ScriptsProvider extends ChangeNotifier {
  final List<Script> _scripts = [];
  bool _loaded = false;

  List<Script> get scripts => List.unmodifiable(_scripts);
  bool get loaded => _loaded;
  int get count => _scripts.length;

  Future<void> load() async {
    try {
      final list = await StorageService.loadScripts();
      _scripts
        ..clear()
        ..addAll(list);
      _scripts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e, st) {
      Log.e('ScriptsProvider', 'load failed', e, st);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    await StorageService.saveScripts(_scripts);
  }

  Future<Script> create({String? title, String? content}) async {
    final now = DateTime.now();
    final id = 's_${now.microsecondsSinceEpoch}';
    final body = content ?? '';
    final t = (title == null || title.trim().isEmpty) ? _autoTitle(body) : title;
    final script = Script(
      id: id,
      title: t,
      content: body,
      createdAt: now,
      updatedAt: now,
    );
    _scripts.insert(0, script);
    notifyListeners();
    await _save();
    Log.i('ScriptsProvider', 'created $id "$t"');
    return script;
  }

  Future<Script> update(String id, {String? title, String? content}) async {
    final idx = _scripts.indexWhere((s) => s.id == id);
    if (idx < 0) {
      throw StateError('Script $id not found');
    }
    final old = _scripts[idx];
    final newContent = content ?? old.content;
    final newTitle = title ?? old.title;
    final finalTitle =
        newTitle.trim().isEmpty ? _autoTitle(newContent) : newTitle;
    final updated = old.copyWith(
      title: finalTitle,
      content: newContent,
      updatedAt: DateTime.now(),
    );
    _scripts.removeAt(idx);
    _scripts.insert(0, updated); // bubble-up
    notifyListeners();
    await _save();
    return updated;
  }

  Future<void> delete(String id) async {
    final removed = _scripts.length;
    _scripts.removeWhere((s) => s.id == id);
    if (_scripts.length != removed) {
      notifyListeners();
      await _save();
      Log.i('ScriptsProvider', 'deleted $id');
    }
  }

  Future<Script> duplicate(String id) async {
    final s = findById(id);
    if (s == null) throw StateError('Script $id not found');
    return create(title: '${s.title} (copie)', content: s.content);
  }

  Script? findById(String id) {
    for (final s in _scripts) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Script> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return scripts;
    return _scripts
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            s.content.toLowerCase().contains(q))
        .toList();
  }

  String _autoTitle(String content) {
    String firstNonEmpty = '';
    for (final l in content.split('\n')) {
      final t = l.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('//')) continue;
      firstNonEmpty = t;
      break;
    }
    if (firstNonEmpty.isEmpty) return 'Sans titre';
    final clean = firstNonEmpty
        .replaceAll(RegExp(r'^#+\s*'), '')
        .replaceAll('**', '')
        .trim();
    if (clean.isEmpty) return 'Sans titre';
    return clean.length > 60 ? '${clean.substring(0, 57)}…' : clean;
  }
}
