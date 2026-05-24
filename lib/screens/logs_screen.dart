import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});
  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _filter = '';
  bool _autoRefresh = true;

  Color _colorFor(String level) {
    switch (level) {
      case 'E': return Colors.redAccent;
      case 'W': return Colors.amber;
      case 'I': return const Color(0xFFD4AF37);
      default:  return Colors.white54;
    }
  }

  void _copyAll() {
    final all = Log.recent().map((e) => e.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: all));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copiés ✓'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    var entries = Log.recent().reversed.toList();
    if (_filter.isNotEmpty) {
      final f = _filter.toLowerCase();
      entries = entries
          .where((e) =>
              e.tag.toLowerCase().contains(f) ||
              e.message.toLowerCase().contains(f) ||
              e.level.toLowerCase().contains(f))
          .toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0F),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Logs', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Auto-refresh',
            icon: Icon(_autoRefresh ? Icons.sync : Icons.sync_disabled,
                color: _autoRefresh ? const Color(0xFFD4AF37) : Colors.white54),
            onPressed: () => setState(() => _autoRefresh = !_autoRefresh),
          ),
          IconButton(
            tooltip: 'Copier tout',
            icon: const Icon(Icons.copy_all, color: Colors.white70),
            onPressed: _copyAll,
          ),
          IconButton(
            tooltip: 'Vider',
            icon: const Icon(Icons.delete_sweep, color: Colors.white70),
            onPressed: () { Log.clear(); setState(() {}); },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                onChanged: (v) => setState(() => _filter = v),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Filtrer (tag, niveau D/I/W/E, mot)',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.filter_list,
                      color: Colors.white54, size: 18),
                  filled: true,
                  fillColor: const Color(0xFF16161D),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _LogsList(
                entries: entries,
                colorFor: _colorFor,
                autoRefresh: _autoRefresh,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.black26,
              child: Center(
                child: Text(
                  '${entries.length} entrées · buffer max 500',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogsList extends StatefulWidget {
  final List<LogEntry> entries;
  final Color Function(String) colorFor;
  final bool autoRefresh;
  const _LogsList({
    required this.entries,
    required this.colorFor,
    required this.autoRefresh,
  });
  @override
  State<_LogsList> createState() => _LogsListState();
}

class _LogsListState extends State<_LogsList> {
  @override
  void initState() {
    super.initState();
    if (widget.autoRefresh) _scheduleRefresh();
  }

  void _scheduleRefresh() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || !widget.autoRefresh) return;
      setState(() {});
      _scheduleRefresh();
    });
  }

  @override
  void didUpdateWidget(_LogsList old) {
    super.didUpdateWidget(old);
    if (widget.autoRefresh && !old.autoRefresh) _scheduleRefresh();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const Center(
        child: Text('Aucun log', style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: widget.entries.length,
      itemBuilder: (_, i) {
        final e = widget.entries[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SelectableText.rich(
            TextSpan(children: [
              TextSpan(
                text: '${e.time.hour.toString().padLeft(2, "0")}:'
                    '${e.time.minute.toString().padLeft(2, "0")}:'
                    '${e.time.second.toString().padLeft(2, "0")} ',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
              TextSpan(
                text: '[${e.level}] ',
                style: TextStyle(
                  color: widget.colorFor(e.level),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: '${e.tag}: ',
                style: const TextStyle(
                    color: Colors.white60, fontSize: 11),
              ),
              TextSpan(
                text: e.message,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ]),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        );
      },
    );
  }
}
