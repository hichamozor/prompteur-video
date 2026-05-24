import 'package:flutter_test/flutter_test.dart';
import 'package:prompteur_video/services/hard_words.dart';

void main() {
  group('HardWords.countSyllables', () {
    test('mots simples', () {
      expect(HardWords.countSyllables('chat'), 1);
      expect(HardWords.countSyllables('table'), 1);
      expect(HardWords.countSyllables('voiture'), 2);
    });
    test('mots avec accents', () {
      expect(HardWords.countSyllables('café'), 2);
      expect(HardWords.countSyllables('hôtel'), 2);
    });
    test('mots longs', () {
      expect(HardWords.countSyllables('ordinateur'), greaterThanOrEqualTo(4));
      expect(HardWords.countSyllables('anticonstitutionnellement'),
          greaterThanOrEqualTo(7));
    });
    test('mot vide', () {
      expect(HardWords.countSyllables(''), 0);
    });
  });

  group('HardWords.isHard', () {
    test('mots faciles ne sont pas durs', () {
      expect(HardWords.isHard('chat'), false);
      expect(HardWords.isHard('voiture'), false);
    });
    test('mots longs sont durs', () {
      expect(HardWords.isHard('ordinateur'), true);
      expect(HardWords.isHard('extraordinaire'), true);
    });
  });

  group('HardWords.findInText', () {
    test('repère les mots durs dans une phrase', () {
      final r = HardWords.findInText("Voici un ordinateur extraordinaire.");
      expect(r.length, greaterThanOrEqualTo(2));
    });
    test('rien si phrase simple', () {
      expect(HardWords.findInText('Le chat est sur le tapis.'), isEmpty);
    });
  });
}
