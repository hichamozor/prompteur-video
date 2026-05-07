import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/script_model.dart';
import '../providers/scripts_provider.dart';
import '../providers/settings_provider.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _newScript({String? content}) async {
    final scripts = context.read<ScriptsProvider>();
    final s = await scripts.create(content: content ?? '');
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(scriptId: s.id)),
    );
  }

  Future<void> _newFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text ?? '';
    if (t.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presse-papier vide')),
      );
      return;
    }
    await _newScript(content: t);
  }

  void _confirmDelete(Script s) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Supprimer ce script ?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(s.title,
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              await context.read<ScriptsProvider>().delete(s.id);
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScriptsProvider>();
    final wpm = context.watch<SettingsProvider>().settings.wpm;
    final scripts = _query.isEmpty ? provider.scripts : provider.search(_query);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.videocam, color: Color(0xFF6C63FF), size: 26),
            SizedBox(width: 10),
            Text('Mes scripts',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 19)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste, color: Colors.white70),
            tooltip: 'Nouveau depuis le presse-papier',
            onPressed: _newFromClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Rechercher un script…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search,
                      color: Colors.white54, size: 20),
                  filled: true,
                  fillColor: const Color(0xFF16213E),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear,
                              color: Colors.white54, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: !provider.loaded
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF6C63FF)))
                  : scripts.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          itemCount: scripts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _ScriptCard(
                            script: scripts[i],
                            wpm: wpm,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => EditorScreen(
                                        scriptId: scripts[i].id))),
                            onDuplicate: () async {
                              await context
                                  .read<ScriptsProvider>()
                                  .duplicate(scripts[i].id);
                            },
                            onDelete: () => _confirmDelete(scripts[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        onPressed: () => _newScript(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau script',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_query.isEmpty ? Icons.description_outlined : Icons.search_off,
                color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            Text(
              _query.isEmpty ? 'Aucun script pour le moment' : 'Aucun résultat',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (_query.isEmpty)
              const Text(
                'Touche le bouton + pour créer ton premier script,\nou colle un texte depuis le presse-papier.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScriptCard extends StatelessWidget {
  final Script script;
  final int wpm;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _ScriptCard({
    required this.script,
    required this.wpm,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
  });

  String _agoFmt(Duration d) {
    if (d.inMinutes < 1) return "à l'instant";
    if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'il y a ${d.inHours} h';
    if (d.inDays < 7) return 'il y a ${d.inDays} j';
    final w = (d.inDays / 7).floor();
    if (w < 5) return 'il y a $w sem.';
    final m = (d.inDays / 30).floor();
    return 'il y a $m mois';
  }

  String _previewLine(String content) {
    for (final l in content.split('\n')) {
      final t = l.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('//')) continue;
      if (t.startsWith('#')) continue;
      return t.replaceAll('**', '');
    }
    return '';
  }

  String _fmtTime(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m < 60) return s == 0 ? '${m}m' : '${m}m${s.toString().padLeft(2, '0')}';
    final h = m ~/ 60;
    return '${h}h${(m % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final words = Script.wordCount(script.content);
    final time = Script.estimatedReadingTime(script.content, wpm: wpm);
    final preview = _previewLine(script.content);
    final ago = _agoFmt(DateTime.now().difference(script.updatedAt));

    return Material(
      color: const Color(0xFF16213E),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      script.title.isEmpty ? 'Sans titre' : script.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(preview,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _meta(Icons.text_snippet_outlined, '$words mots'),
                        _meta(Icons.timer_outlined, _fmtTime(time)),
                        Text('· $ago',
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                color: const Color(0xFF1A1A2E),
                icon: const Icon(Icons.more_vert,
                    color: Colors.white54, size: 20),
                onSelected: (v) {
                  if (v == 'duplicate') onDuplicate();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'duplicate',
                      child: Row(children: [
                        Icon(Icons.copy, size: 18, color: Colors.white70),
                        SizedBox(width: 10),
                        Text('Dupliquer',
                            style: TextStyle(color: Colors.white)),
                      ])),
                  PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: Colors.redAccent),
                        SizedBox(width: 10),
                        Text('Supprimer',
                            style: TextStyle(color: Colors.redAccent)),
                      ])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white38),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      );
}
