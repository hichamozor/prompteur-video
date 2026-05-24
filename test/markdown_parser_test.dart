import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompteur_video/services/markdown_parser.dart';

void main() {
  group('PrompterMarkdown.strip', () {
    test('removes // comments', () {
      const input = 'ligne 1\n// note\nligne 2';
      expect(PrompterMarkdown.strip(input), 'ligne 1\nligne 2');
    });
    test('removes section headers', () {
      const input = '# Intro\nbonjour\n## Sub\nplop';
      expect(PrompterMarkdown.strip(input), 'Intro\nbonjour\nSub\nplop');
    });
    test('removes ** for bold', () {
      const input = 'mot **important** ici';
      expect(PrompterMarkdown.strip(input), 'mot important ici');
    });
    test('removes leading whitespace before #', () {
      const input = '  # Titre\n  texte';
      expect(PrompterMarkdown.strip(input), 'Titre\n  texte');
    });
  });

  group('PrompterMarkdown.extractKeywords', () {
    test('returns empty when no bold', () {
      expect(PrompterMarkdown.extractKeywords('plain text'), isEmpty);
    });

    test('extracts single keyword', () {
      final r = PrompterMarkdown.extractKeywords('Ceci est **important**.');
      expect(r.length, 1);
      expect(r[0].text, 'important');
      expect(r[0].section, isNull);
    });

    test('multiple keywords with section', () {
      const txt = '# Intro\nVoici **mot1** et **mot2**.\n# Conclusion\n**fin**';
      final r = PrompterMarkdown.extractKeywords(txt);
      expect(r.length, 3);
      expect(r[0].text, 'mot1');
      expect(r[0].section, 'Intro');
      expect(r[1].text, 'mot2');
      expect(r[1].section, 'Intro');
      expect(r[2].text, 'fin');
      expect(r[2].section, 'Conclusion');
    });

    test('ignores comments', () {
      const txt = '// **dans-un-commentaire**\nvrai **kw**';
      final r = PrompterMarkdown.extractKeywords(txt);
      expect(r.length, 1);
      expect(r[0].text, 'kw');
    });
  });

  group('PrompterMarkdown.parse', () {
    test('returns a TextSpan with children', () {
      final span = PrompterMarkdown.parse(
        'plain **bold** more',
        textColor: Colors.white,
        sectionColor: Colors.yellow,
        commentColor: Colors.grey,
        fontSize: 16,
        baseWeight: FontWeight.normal,
      );
      expect(span, isA<TextSpan>());
      final ts = span as TextSpan;
      expect(ts.children, isNotNull);
      expect(ts.children!.length, greaterThan(1));
    });
  });
}
