import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'prompter_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      _textController.text = data!.text!;
      context.read<SettingsProvider>().updateScript(data.text!);
    }
  }

  void _start() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrez votre texte avant de démarrer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    context.read<SettingsProvider>().updateScript(text);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PrompterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final settings = provider.settings;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.videocam, color: Color(0xFF6C63FF), size: 26),
            SizedBox(width: 10),
            Text(
              'Prompteur Vidéo',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Zone de texte
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF16213E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Votre script',
                              style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                          Row(
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.content_paste, size: 15),
                                label: const Text('Coller'),
                                onPressed: _paste,
                                style: TextButton.styleFrom(foregroundColor: const Color(0xFF6C63FF)),
                              ),
                              IconButton(
                                icon: Icon(Icons.clear, size: 18, color: Colors.red[300]),
                                onPressed: () {
                                  _textController.clear();
                                  provider.updateScript('');
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          expands: true,
                          style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                          decoration: const InputDecoration(
                            hintText: 'Entrez ou collez votre texte ici...',
                            hintStyle: TextStyle(color: Colors.white24),
                            border: InputBorder.none,
                          ),
                          onChanged: provider.updateScript,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Réglages rapides
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF16213E),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  children: [
                    _QuickSlider(
                      icon: Icons.speed,
                      label: 'Vitesse',
                      value: settings.scrollSpeed,
                      min: 20,
                      max: 300,
                      display: '${settings.scrollSpeed.round()}',
                      onChanged: provider.updateScrollSpeed,
                    ),
                    const SizedBox(height: 6),
                    _QuickSlider(
                      icon: Icons.text_fields,
                      label: 'Taille',
                      value: settings.fontSize,
                      min: 18,
                      max: 80,
                      display: '${settings.fontSize.round()}px',
                      onChanged: provider.updateFontSize,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Bouton démarrer
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_circle_filled, size: 26),
                  label: const Text('DÉMARRER',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  onPressed: _start,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  const _QuickSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6C63FF), size: 18),
        const SizedBox(width: 8),
        SizedBox(width: 52, child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13))),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: Color(0xFF6C63FF),
              thumbColor: Color(0xFF6C63FF),
              inactiveTrackColor: Colors.white24,
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(display, style: const TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.right),
        ),
      ],
    );
  }
}
