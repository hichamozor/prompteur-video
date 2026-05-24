/// Détection de mots "durs" (long, complexes) pour ralentir auto le défilement.
///
/// Heuristique syllabes français-friendly :
///   - voyelles (incl. accentuées) → "noyaux" syllabiques
///   - clusters de voyelles consécutives = 1 syllabe (ai, eu, ou, eau...)
///   - 'e' final muet ne compte pas
///
/// Un mot est "dur" si ≥ 4 syllabes estimées.
class HardWords {
  static const int minSyllables = 4;

  /// Estime le nombre de syllabes d'un mot français.
  static int countSyllables(String word) {
    if (word.isEmpty) return 0;
    final w = word.toLowerCase();
    final vowels = RegExp(r'[aeiouyàâäéèêëîïôöùûü]+');
    final matches = vowels.allMatches(w);
    int count = matches.length;
    // Retire le 'e' final muet (ex: "table", "fenêtre")
    if (count > 1 && w.endsWith('e') &&
        !RegExp(r'[aeiouyàâäéèêëîïôöùûü]e$').hasMatch(w)) {
      count -= 1;
    }
    return count < 1 ? 1 : count;
  }

  static bool isHard(String word) => countSyllables(word) >= minSyllables;

  /// Position des mots durs dans un texte (offset début/fin sur la string brute).
  static List<({int start, int end})> findInText(String text) {
    final result = <({int start, int end})>[];
    final wordRe = RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ]+(?:[''-][A-Za-zÀ-ÖØ-öø-ÿ]+)*");
    for (final m in wordRe.allMatches(text)) {
      if (isHard(m.group(0)!)) {
        result.add((start: m.start, end: m.end));
      }
    }
    return result;
  }

  /// Multiplicateur de vitesse à appliquer en fonction de la position scroll
  /// dans le texte. Renvoie 0.8 (= -20%) si on est sur une ligne contenant un
  /// mot dur, sinon 1.0.
  ///
  /// Pour rester simple : on ne calcule pas la position pixel exacte, on
  /// regarde juste si la *fenêtre visible* (autour du milieu de l'écran)
  /// contient un mot dur.
  static double slowdownForLine(String line) {
    return findInText(line).isEmpty ? 1.0 : 0.8;
  }
}
