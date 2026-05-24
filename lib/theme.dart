import 'package:flutter/material.dart';

/// Palette unique de l'app — noir + or.
///
/// Conventions :
///   - bg* : fonds (du plus sombre au plus clair)
///   - text* : niveaux de gris pour le texte
///   - gold* : accents principaux
///   - alert* : couleurs sémantiques (REC, succès, etc.)
class AppColors {
  // ── Fonds (plus sombre vers plus clair)
  static const Color bg = Color(0xFF0B0B0F);            // background app
  static const Color bgRaised = Color(0xFF13131A);      // input fields, search bar
  static const Color surface = Color(0xFF16161D);       // cards
  static const Color surfaceHi = Color(0xFF1F1F28);     // elevated/hover

  // ── Bordures et séparateurs
  static const Color borderSubtle = Color(0x14FFFFFF);  // 8% blanc
  static const Color borderDefault = Color(0x1FFFFFFF); // 12% blanc
  static const Color divider = Color(0x12FFFFFF);       // 7% blanc

  // ── Texte
  static const Color textPrimary = Color(0xFFFFFFFF);   // blanc pur
  static const Color textSecondary = Color(0xA6FFFFFF); // 65%
  static const Color textTertiary = Color(0x59FFFFFF);  // 35%
  static const Color textDisabled = Color(0x33FFFFFF);  // 20%

  // ── Or (accent principal)
  static const Color gold = Color(0xFFD4AF37);          // or fin, primary
  static const Color goldLight = Color(0xFFF2D27E);     // hover, badges
  static const Color goldDark = Color(0xFF8B6F2A);      // bordures, dim
  static const Color goldGlow = Color(0x33D4AF37);      // 20% gold pour halos

  // ── Sémantique
  static const Color rec = Color(0xFFE53935);
  static const Color recDot = Color(0xFFFF5252);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFA726);

  // ── Sections markdown (un peu plus chaud que le gold pour différencier)
  static const Color section = Color(0xFFE8C470);
}

class AppRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
}

class AppText {
  static const TextStyle title = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );
  static const TextStyle headerLabel = TextStyle(
    color: AppColors.gold,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.8,
  );
  static const TextStyle body = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodyMuted = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 13,
  );
  static const TextStyle caption = TextStyle(
    color: AppColors.textTertiary,
    fontSize: 11,
  );
}
