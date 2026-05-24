import 'package:flutter/material.dart';

import '../theme.dart';
import 'logs_screen.dart';
import 'prompter_screen.dart';
import 'settings_screen.dart';

/// Page d'accueil minimaliste : un gros bouton "Démarrer" qui ouvre
/// directement le prompteur (caméra + serveur WiFi prêts), avec un texte vide.
/// Les scripts sont poussés depuis le PC via la page de contrôle.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Barre du haut : titre + icônes paramètres/logs
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.videocam, color: AppColors.gold, size: 26),
                  const SizedBox(width: 10),
                  const Text(
                    'Prompteur',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Logs WiFi',
                    icon: const Icon(Icons.bug_report_outlined,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LogsScreen()),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Paramètres',
                    icon: const Icon(Icons.settings,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),

            // ── Zone centrale : bouton géant
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StartButton(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PrompterScreen()),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'DÉMARRER',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Lance la caméra + active la page de contrôle WiFi.\nColle ton script depuis le PC.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary.withValues(alpha: 0.55),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer discret
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi,
                      color: AppColors.gold.withValues(alpha: 0.6), size: 12),
                  const SizedBox(width: 6),
                  Text(
                    'Le téléphone et le PC doivent être sur le même WiFi',
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.35),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton circulaire géant, halo doré, animation pulse au pressed.
class _StartButton extends StatefulWidget {
  final VoidCallback onTap;
  const _StartButton({required this.onTap});

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          // Pulse doux entre 0.2 et 0.45 de transparence du halo
          final t = (1 - (_ctrl.value - 0.5).abs() * 2); // 0→1→0
          final glow = 0.2 + 0.25 * t;
          return Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  AppColors.goldLight,
                  AppColors.gold,
                ],
                stops: [0.0, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: glow),
                  blurRadius: 50,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                size: 110,
                color: AppColors.bg,
              ),
            ),
          );
        },
      ),
    );
  }
}
