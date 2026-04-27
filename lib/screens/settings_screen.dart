import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../models/settings_model.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final s = provider.settings;

    void upd(PrompterSettings ns) => provider.updateSettings(ns);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text('Paramètres', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── TEXTE ──────────────────────────────────────────────
          _Header('TEXTE'),
          _Card([
            _Slider(
              icon: Icons.text_fields, label: 'Taille de police',
              value: s.fontSize, min: 16, max: 80, divs: 32,
              display: '${s.fontSize.round()}px',
              onChanged: provider.updateFontSize,
            ),
            _Div(),
            _Slider(
              icon: Icons.format_line_spacing, label: 'Interligne',
              value: s.lineSpacing, min: 1.0, max: 3.0, divs: 20,
              display: s.lineSpacing.toStringAsFixed(1),
              onChanged: (v) => upd(s.copyWith(lineSpacing: v)),
            ),
            _Div(),
            _Slider(
              icon: Icons.margin, label: 'Marges',
              value: s.marginHorizontal, min: 0, max: 64, divs: 16,
              display: '${s.marginHorizontal.round()}',
              onChanged: (v) => upd(s.copyWith(marginHorizontal: v)),
            ),
            _Div(),
            ListTile(
              leading: const Icon(Icons.font_download, color: Color(0xFF6C63FF), size: 20),
              title: const Text('Police', style: TextStyle(color: Colors.white70, fontSize: 14)),
              trailing: DropdownButton<String>(
                value: s.fontFamily,
                dropdownColor: const Color(0xFF16213E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'Default', child: Text('Par défaut')),
                  DropdownMenuItem(value: 'serif', child: Text('Serif')),
                  DropdownMenuItem(value: 'monospace', child: Text('Monospace')),
                  DropdownMenuItem(value: 'sans-serif-condensed', child: Text('Condensé')),
                  DropdownMenuItem(value: 'sans-serif-light', child: Text('Light')),
                ],
                onChanged: (v) => upd(s.copyWith(fontFamily: v ?? 'Default')),
              ),
            ),
            _Div(),
            ListTile(
              leading: const Icon(Icons.format_align_center, color: Color(0xFF6C63FF), size: 20),
              title: const Text('Alignement', style: TextStyle(color: Colors.white70, fontSize: 14)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AlignBtn(Icons.format_align_left, s.textAlign == TextAlign.left,
                      () => upd(s.copyWith(textAlign: TextAlign.left))),
                  _AlignBtn(Icons.format_align_center, s.textAlign == TextAlign.center,
                      () => upd(s.copyWith(textAlign: TextAlign.center))),
                  _AlignBtn(Icons.format_align_right, s.textAlign == TextAlign.right,
                      () => upd(s.copyWith(textAlign: TextAlign.right))),
                ],
              ),
            ),
          ]),

          // ── COULEURS ────────────────────────────────────────────
          _Header('COULEURS'),
          _Card([
            ListTile(
              leading: const Icon(Icons.color_lens, color: Color(0xFF6C63FF), size: 20),
              title: const Text('Couleur du texte', style: TextStyle(color: Colors.white70, fontSize: 14)),
              trailing: _ColorRow(
                selected: s.textColor,
                colors: const [
                  Colors.white, Colors.yellow, Colors.greenAccent,
                  Colors.cyanAccent, Colors.orangeAccent, Colors.pinkAccent,
                ],
                onPick: (c) => upd(s.copyWith(textColor: c)),
              ),
            ),
            _Div(),
            ListTile(
              leading: const Icon(Icons.rectangle, color: Color(0xFF6C63FF), size: 20),
              title: const Text('Fond du texte', style: TextStyle(color: Colors.white70, fontSize: 14)),
              trailing: _ColorRow(
                selected: s.backgroundColor,
                colors: const [
                  Colors.black, Colors.white, Colors.indigo,
                  Colors.teal, Colors.brown, Colors.blueGrey,
                ],
                onPick: (c) => upd(s.copyWith(backgroundColor: c)),
              ),
            ),
            _Div(),
            _Slider(
              icon: Icons.opacity, label: 'Opacité du fond',
              value: s.backgroundOpacity, min: 0, max: 1, divs: 20,
              display: '${(s.backgroundOpacity * 100).round()}%',
              onChanged: (v) => upd(s.copyWith(backgroundOpacity: v)),
            ),
          ]),

          // ── DÉFILEMENT ─────────────────────────────────────────
          _Header('DÉFILEMENT'),
          _Card([
            _Slider(
              icon: Icons.speed, label: 'Vitesse',
              value: s.scrollSpeed, min: 20, max: 300, divs: 28,
              display: '${s.scrollSpeed.round()}',
              onChanged: provider.updateScrollSpeed,
            ),
            _Div(),
            ListTile(
              leading: const Icon(Icons.timer, color: Color(0xFF6C63FF), size: 20),
              title: const Text('Compte à rebours', style: TextStyle(color: Colors.white70, fontSize: 14)),
              trailing: DropdownButton<int>(
                value: s.countdownSeconds,
                dropdownColor: const Color(0xFF16213E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Aucun')),
                  DropdownMenuItem(value: 3, child: Text('3 secondes')),
                  DropdownMenuItem(value: 5, child: Text('5 secondes')),
                  DropdownMenuItem(value: 10, child: Text('10 secondes')),
                ],
                onChanged: (v) => upd(s.copyWith(countdownSeconds: v ?? 3)),
              ),
            ),
          ]),

          // ── CAMÉRA ─────────────────────────────────────────────
          _Header('CAMÉRA'),
          _Card([
            _Switch(Icons.videocam, 'Afficher la caméra', s.showCamera,
                (v) => upd(s.copyWith(showCamera: v))),
            _Div(),
            _Switch(Icons.camera_front, 'Caméra frontale', s.useFrontCamera,
                (v) => upd(s.copyWith(useFrontCamera: v))),
            _Div(),
            _Switch(Icons.flip, 'Mode miroir', s.mirrorMode,
                (v) => upd(s.copyWith(mirrorMode: v))),
          ]),

          // ── AFFICHAGE ──────────────────────────────────────────
          _Header('AFFICHAGE'),
          _Card([
            _Switch(Icons.screen_lock_landscape, "Garder l'écran allumé", s.keepScreenOn,
                (v) => upd(s.copyWith(keepScreenOn: v))),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String title;
  const _Header(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6, left: 4),
        child: Text(title,
            style: const TextStyle(
                color: Color(0xFF6C63FF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.8)),
      );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card(this.children);
  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFF16213E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)),
      );
}

class _Div extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const Divider(color: Colors.white12, height: 1, indent: 16, endIndent: 16);
}

class _Slider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value, min, max;
  final int divs;
  final String display;
  final ValueChanged<double> onChanged;

  const _Slider({
    required this.icon, required this.label, required this.value,
    required this.min, required this.max, required this.divs,
    required this.display, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6C63FF), size: 20),
            const SizedBox(width: 10),
            SizedBox(
                width: 110,
                child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
            Expanded(
              child: SliderTheme(
                data: const SliderThemeData(
                  activeTrackColor: Color(0xFF6C63FF),
                  thumbColor: Color(0xFF6C63FF),
                  inactiveTrackColor: Colors.white24,
                  trackHeight: 2,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                    value: value.clamp(min, max),
                    min: min, max: max, divisions: divs,
                    onChanged: onChanged),
              ),
            ),
            SizedBox(
                width: 46,
                child: Text(display,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.right)),
          ],
        ),
      );
}

class _Switch extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Switch(this.icon, this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: const Color(0xFF6C63FF), size: 20),
        title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        trailing: Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFF6C63FF)),
      );
}

class _ColorRow extends StatelessWidget {
  final Color selected;
  final List<Color> colors;
  final ValueChanged<Color> onPick;

  const _ColorRow({required this.selected, required this.colors, required this.onPick});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: colors
            .map((c) => GestureDetector(
                  onTap: () => onPick(c),
                  child: Container(
                    width: 24, height: 24,
                    margin: const EdgeInsets.only(left: 5),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected.value == c.value ? const Color(0xFF6C63FF) : Colors.white30,
                        width: selected.value == c.value ? 2.5 : 1,
                      ),
                    ),
                  ),
                ))
            .toList(),
      );
}

class _AlignBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _AlignBtn(this.icon, this.active, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32, height: 32,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF6C63FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? const Color(0xFF6C63FF) : Colors.white30),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );
}
