import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/core/models/intent.dart';
import 'package:noor_ai/core/utils/intent_parser.dart';

void main() {
  group('IntentParser emotional routing', () {
    final parser = IntentParser.instance;

    test('routes peace of mind phrasing to emotional guidance', () {
      final intent = parser.parse('I lost my peace of mind');

      expect(intent.type, IntentType.emotionalGuidance);
      expect(intent.emotion, 'anxiety');
    });

    test('routes overwhelmed phrasing to emotional guidance', () {
      final intent = parser.parse('Lately I feel overwhelmed by life');

      expect(intent.type, IntentType.emotionalGuidance);
      expect(intent.emotion, 'stress');
    });

    test('routes heavy heart phrasing to emotional guidance', () {
      final intent = parser.parse('My heart feels heavy today');

      expect(intent.type, IntentType.emotionalGuidance);
      expect(intent.emotion, 'sadness');
    });

    test('routes bare peace prompt to emotional guidance', () {
      final intent = parser.parse('peace');

      expect(intent.type, IntentType.emotionalGuidance);
      expect(intent.emotion, 'peace');
    });

    test('keeps broad peace questions as general questions', () {
      final intent = parser.parse('What does the Quran say about peace?');

      expect(intent.type, IntentType.askGeneralQuestion);
    });

    test('keeps verse explain routing ahead of emotion phrases', () {
      final intent = parser.parse('Explain verse 2:255');

      expect(intent.type, IntentType.explainAyah);
      expect(intent.verseKey, '2:255');
    });

    test('parses explain surah al maida from typed chat phrasing', () {
      final intent = parser.parse('Explain surah al maida via chat text');

      expect(intent.type, IntentType.explainSurah);
      expect(intent.surahNumber, 5);
    });
  });

  group('IntentParser named-verse routing', () {
    final parser = IntentParser.instance;

    test('routes "ayatul kursi" to explainAyah 2:255', () {
      final intent = parser.parse('ayatul kursi');

      expect(intent.type, IntentType.explainAyah);
      expect(intent.surahNumber, 2);
      expect(intent.ayahNumber, 255);
    });

    test('routes "ayat kursi" to explainAyah 2:255', () {
      final intent = parser.parse('ayat kursi');

      expect(intent.type, IntentType.explainAyah);
      expect(intent.surahNumber, 2);
      expect(intent.ayahNumber, 255);
    });

    test('routes bare "kursi" to explainAyah 2:255', () {
      final intent = parser.parse('kursi');

      expect(intent.type, IntentType.explainAyah);
      expect(intent.surahNumber, 2);
      expect(intent.ayahNumber, 255);
    });

    test('routes "explain ayatul kursi" via contains-match to explainAyah 2:255', () {
      final intent = parser.parse('explain ayatul kursi');

      expect(intent.type, IntentType.explainAyah);
      expect(intent.surahNumber, 2);
      expect(intent.ayahNumber, 255);
    });

    test('routes "what is ayatul kursi" via contains-match to explainAyah 2:255', () {
      final intent = parser.parse('what is ayatul kursi');

      expect(intent.type, IntentType.explainAyah);
      expect(intent.surahNumber, 2);
      expect(intent.ayahNumber, 255);
    });

    test('routes "fatiha" to explainSurah 1', () {
      final intent = parser.parse('fatiha');

      expect(intent.type, IntentType.explainSurah);
      expect(intent.surahNumber, 1);
    });

    test('routes "al fatiha" to explainSurah 1', () {
      final intent = parser.parse('al fatiha');

      expect(intent.type, IntentType.explainSurah);
      expect(intent.surahNumber, 1);
    });

    test('routes "ayat noor" to explainAyah 24:35', () {
      final intent = parser.parse('ayat noor');

      expect(intent.type, IntentType.explainAyah);
      expect(intent.surahNumber, 24);
      expect(intent.ayahNumber, 35);
    });

    test('routes "verse of light" to explainAyah 24:35', () {
      final intent = parser.parse('verse of light');

      expect(intent.type, IntentType.explainAyah);
      expect(intent.surahNumber, 24);
      expect(intent.ayahNumber, 35);
    });

    test('routes "throne verse" to explainAyah 2:255', () {
      final intent = parser.parse('throne verse');

      expect(intent.type, IntentType.explainAyah);
      expect(intent.surahNumber, 2);
      expect(intent.ayahNumber, 255);
    });
  });
}