import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/script_model.dart';
import '../models/settings_model.dart';
import '../providers/scripts_provider.dart';
import '../providers/settings_provider.dart';
import 'prompter_screen.dart';
import 'settings_screen.dart';

class EditorScreen extends StatefulWidget {
  final String scriptId;
  const EditorScreen({super.key, required this.scriptId});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  Timer? _saveTimer;
  bool _dirty = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadScript());
    _bodyCtrl.addListener(_onBodyChanged);
    _titleCtrl.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _flushSave();
    _saveTimer?.cancel();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _loadScript() {
    final s = context.read<ScriptsProvider>().findById(widget.scriptId);
    if (s == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Script introuvable')));
      Navigator.pop(context);
      return;
    }
    _titleCtrl.text = s.title;
    _bodyCtrl.text = s.content;
    setState(() => _loaded = true);
  }

  void _onBodyChanged() {
    if (!_loaded) return;
    setState(() {}); // refresh stats
    _scheduleSave();
  }

  void _onTitleChanged() {
    if (!_loaded) return;
    _scheduleSave();
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flushSave);
  }

  Future<void> _flushSave() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      await context.read<ScriptsProvider>().update(
            widget.scriptId,
            title: _titleCtrl.text,
            content: _bodyCtrl.text,
          );
    } catch (_) {
      // script supprimé pendant l'édition — ignore
    }
  }

  Future<void> _start() async {
    if (_bodyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le script est vide'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await _flushSave();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrompterScreen(scriptId: widget.scriptId),
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final cur = _bodyCtrl.text;
    final selection = _bodyCtrl.selection;
    final start = selection.start >= 0 ? selection.start : cur.length;
    final end = selection.end >= 0 ? selection.end : cur.length;
    final next = cur.replaceRange(start, end, data.text!);
    _bodyCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + data.text!.length),
    );
  }

  void _showPresets() {
    final settings = context.read<SettingsProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 12),
                child: Text(
                  'PRESET RAPIDE',
                  style: TextStyle(
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontSize: 12),
                ),
              ),
              _PresetTile(
                icon: Icons.music_note,
                label: 'TikTok',
                subtitle: '1080p · 30 fps · safe-zone · vitesse rapide',
                onTap: () {
                  settings.applyPreset(PrompterSettings.tiktok);
                  Navigator.pop(context);
                  _toast('Preset TikTok appliqué');
                },
              ),
              _PresetTile(
                icon: Icons.play_circle_outline,
                label: 'YouTube Short',
                subtitle: '4K · 30 fps · plus grande police',
                onTap: () {
                  settings.applyPreset(PrompterSettings.youtubeShort);
                  Navigator.pop(context);
                  _toast('Preset YouTube Short appliqué');
                },
              ),
              _PresetTile(
                icon: Icons.camera_alt_outlined,
                label: 'Instagram Reels',
                subtitle: '1080p · 30 fps · safe-zone',
                onTap: () {
                  settings.applyPreset(PrompterSettings.reels);
                  Navigator.pop(context);
                  _toast('Preset Reels appliqué');
                },
              ),
              _PresetTile(
                icon: Icons.mic_none,
                label: 'Podcast / Audio',
                subtitle: '4K · pas de caméra · vitesse posée',
                onTap: () {
                  settings.applyPreset(PrompterSettings.podcast);
                  Navigator.pop(context);
                  _toast('Preset Podcast appliqué');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF6C63FF),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    await _flushSave();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
      );
    }
    final wpm = context.watch<SettingsProvider>().settings.wpm;
    final words = Script.wordCount(_bodyCtrl.text);
    final time = Script.estimatedReadingTime(_bodyCtrl.text, wpm: wpm);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: TextField(
            controller: _titleCtrl,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Sans titre',
              hintStyle: TextStyle(color: Colors.white24),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white70),
              tooltip: 'Presets rapides',
              onPressed: _showPresets,
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white70),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    children: [
                      _Stat(
                          icon: Icons.text_snippet_outlined,
                          label: '$words mots'),
                      const SizedBox(width: 14),
                      _Stat(icon: Icons.timer_outlined, label: _fmtTime(time)),
                      const SizedBox(width: 14),
                      _Stat(icon: Icons.speed, label: '$wpm wpm'),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.content_paste, size: 15),
                        label: const Text('Coller'),
                        onPressed: _paste,
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF6C63FF)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF16213E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      controller: _bodyCtrl,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16, height: 1.55),
                      decoration: const InputDecoration(
                        hintText:
                            'Écris ou colle ton script ici…\n\nAstuces :\n  **gras**  →  emphase\n  # Section  →  marqueur\n  // commentaire  →  pour toi seulement',
                        hintStyle:
                            TextStyle(color: Colors.white24, height: 1.5),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_circle_filled, size: 26),
                    label: const Text('DÉMARRER',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                    onPressed: _start,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Stat({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      );
}

class _PresetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _PresetTile(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: const Color(0xFF6C63FF)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      size: 14, color: Colors.white38),
                ],
              ),
            ),
          ),
        ),
      );
}

String _fmtTime(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  if (m < 60) return s == 0 ? '${m}m00' : '${m}m${s.toString().padLeft(2, '0')}';
  final h = m ~/ 60;
  return '${h}h${(m % 60).toString().padLeft(2, '0')}';
}
