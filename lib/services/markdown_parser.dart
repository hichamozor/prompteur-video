import 'package:flutter/material.dart';

/// Parser markdown léger pour le prompteur :
///   **gras**     → texte en gras (les ** sont masqués)
///   # Section    → titre coloré, plus grand (le # est masqué)
///   ## Section   → titre coloré, légèrement plus grand
///   // commentaire → notes perso, italique gris, taille réduite
class PrompterMarkdown {
  /// Construit les TextSpans pour le rendu prompter.
  static InlineSpan parse(
    String text, {
    required Color textColor,
    required Color sectionColor,
    required Color commentColor,
    required double fontSize,
    required FontWeight baseWeight,
    String? fontFamily,
  }) {
    final children = <TextSpan>[];
    final lines = text.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLast = i == lines.length - 1;
      final newline = isLast ? '' : '\n';

      // Commentaire — toute la ligne est en gris/italique
      if (line.trimLeft().startsWith('//')) {
        children.add(TextSpan(
          text: '$line$newline',
          style: TextStyle(
            color: commentColor,
            fontStyle: FontStyle.italic,
            fontSize: fontSize * 0.72,
            fontWeight: FontWeight.w400,
          ),
        ));
        continue;
      }

      // Section — # ou ## en début de ligne
      final secMatch = RegExp(r'^(\s*)(#{1,3})\s+(.*)$').firstMatch(line);
      if (secMatch != null) {
        final indent = secMatch.group(1)!;
        final hashes = secMatch.group(2)!;
        final content = secMatch.group(3)!;
        final scale = hashes.length == 1 ? 1.18 : (hashes.length == 2 ? 1.08 : 1.02);
        if (indent.isNotEmpty) children.add(TextSpan(text: indent));
        children.add(TextSpan(
          text: '$content$newline',
          style: TextStyle(
            color: sectionColor,
            fontWeight: FontWeight.w900,
            fontSize: fontSize * scale,
            letterSpacing: 0.5,
          ),
        ));
        continue;
      }

      _appendBoldSpans(line, children);
      if (newline.isNotEmpty) children.add(TextSpan(text: newline));
    }

    return TextSpan(
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: baseWeight,
        fontFamily: fontFamily,
      ),
      children: children,
    );
  }

  static void _appendBoldSpans(String line, List<TextSpan> out) {
    final re = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final m in re.allMatches(line)) {
      if (m.start > last) {
        out.add(TextSpan(text: line.substring(last, m.start)));
      }
      out.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ));
      last = m.end;
    }
    if (last < line.length) {
      out.add(TextSpan(text: line.substring(last)));
    }
  }

  /// Strip markdown : utile pour le compteur de mots / temps de lecture.
  /// Retire les commentaires, les # de section et les ** d'emphase.
  static String strip(String text) {
    return text
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .map((l) => l.replaceAll(RegExp(r'^\s*#+\s+'), '').replaceAll('**', ''))
        .join('\n');
  }
}
