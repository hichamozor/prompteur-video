import '../services/markdown_parser.dart';

class Script {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Script({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  Script copyWith({
    String? title,
    String? content,
    DateTime? updatedAt,
  }) {
    return Script(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Script.fromJson(Map<String, dynamic> j) {
    DateTime parse(dynamic v) {
      if (v is String) {
        try { return DateTime.parse(v); } catch (_) {}
      }
      return DateTime.now();
    }
    return Script(
      id: (j['id'] as String?) ?? 's_${DateTime.now().microsecondsSinceEpoch}',
      title: (j['title'] as String?) ?? 'Sans titre',
      content: (j['content'] as String?) ?? '',
      createdAt: parse(j['createdAt']),
      updatedAt: parse(j['updatedAt']),
    );
  }

  // ── Stats utilitaires (ignorent le markdown léger)

  /// Nombre de mots "lus" (commentaires // exclus, ## de section ignorés).
  static int wordCount(String content) {
    final stripped = PrompterMarkdown.strip(content);
    return stripped
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
  }

  /// Temps de lecture estimé (par défaut 150 mots/min FR).
  static Duration estimatedReadingTime(String content, {int wpm = 150}) {
    if (wpm <= 0) wpm = 150;
    final words = wordCount(content);
    final seconds = (words / wpm * 60).round();
    return Duration(seconds: seconds);
  }
}
