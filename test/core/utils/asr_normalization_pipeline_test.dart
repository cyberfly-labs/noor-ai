import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/core/models/intent.dart';
import 'package:noor_ai/core/utils/asr_normalization_pipeline.dart';

void main() {
  final pipeline = AsrNormalizationPipeline.instance;

  // ── Stage 1-2: Text cleaning + term corrections ────────────────────────────

  group('text cleaning and term corrections', () {
    test('lowercases and strips punctuation', () {
      final result = pipeline.process('SURAH Al-Baqarah!');
      expect(result.cleanText, isNot(contains('!')));
      expect(result.cleanText, equals(result.cleanText.toLowerCase()));
    });

    test('corrects "bakara" → "baqarah" surah name', () {
      final result = pipeline.process('surah bakara 255');
      expect(result.surahNumber, 2);
      expect(result.ayahNumber, 255);
    });

    test('corrects "yaseen" → "yasin"', () {
      final result = pipeline.process('explain surah yaseen');
      expect(result.surahNumber, 36);
      expect(result.intent, IntentType.explainSurah);
    });

    test('corrects "rahmaan" → "rahman"', () {
      final result = pipeline.process('explain surah rahmaan');
      expect(result.surahNumber, 55);
    });

    test('corrects "tafseer" → "tafsir" intent', () {
      final result = pipeline.process('tafseer of baqarah 255');
      expect(result.intent, IntentType.tafsir);
      expect(result.surahNumber, 2);
    });

    test('corrects "rukh" → "mulk"', () {
      final result = pipeline.process('play surah rukh');
      expect(result.surahNumber, 67);
      expect(result.intent, IntentType.playAudio);
    });

    test('corrects multi-word phrase "ya seen" → "yasin"', () {
      final result = pipeline.process('explain ya seen');
      expect(result.surahNumber, 36);
    });

    test('normalises "surahX" (no space) → "surah X"', () {
      final result = pipeline.process('surahikhlas meaning');
      expect(result.surahNumber, 112);
    });
  });

  // ── Stage 3: Named-verse alias lookup ──────────────────────────────────────

  group('named-verse alias lookup', () {
    test('exact "ayatul kursi" → explainAyah 2:255', () {
      final result = pipeline.process('ayatul kursi');
      expect(result.intent, IntentType.explainAyah);
      expect(result.surahNumber, 2);
      expect(result.ayahNumber, 255);
      expect(result.needsLlmFallback, false);
    });

    test('exact "kursi" → 2:255', () {
      final result = pipeline.process('kursi');
      expect(result.surahNumber, 2);
      expect(result.ayahNumber, 255);
    });

    test('contains "explain ayatul kursi" → 2:255', () {
      final result = pipeline.process('explain ayatul kursi');
      expect(result.intent, IntentType.explainAyah);
      expect(result.surahNumber, 2);
      expect(result.ayahNumber, 255);
    });

    test('"throne verse" → 2:255', () {
      final result = pipeline.process('throne verse');
      expect(result.surahNumber, 2);
      expect(result.ayahNumber, 255);
    });

    test('"fatiha" → explainSurah 1', () {
      final result = pipeline.process('fatiha');
      expect(result.intent, IntentType.explainSurah);
      expect(result.surahNumber, 1);
      expect(result.ayahNumber, isNull);
    });

    test('"ayat noor" → explainAyah 24:35', () {
      final result = pipeline.process('ayat noor');
      expect(result.surahNumber, 24);
      expect(result.ayahNumber, 35);
    });

    test('"verse of light" → 24:35', () {
      final result = pipeline.process('verse of light');
      expect(result.surahNumber, 24);
      expect(result.ayahNumber, 35);
    });

    test('"ayat saif" → 9:5', () {
      final result = pipeline.process('ayat saif');
      expect(result.surahNumber, 9);
      expect(result.ayahNumber, 5);
    });
  });

  // ── Stage 4: Surah + ayah extraction ──────────────────────────────────────

  group('surah + ayah extraction', () {
    test('colon format "2:255"', () {
      final result = pipeline.process('2:255');
      expect(result.surahNumber, 2);
      expect(result.ayahNumber, 255);
    });

    test('"surah bakra 255" (named + bare number)', () {
      final result = pipeline.process('surah bakra 255');
      expect(result.surahNumber, 2);
      expect(result.ayahNumber, 255);
    });

    test('"surah baqarah ayah 255"', () {
      final result = pipeline.process('surah baqarah ayah 255');
      expect(result.surahNumber, 2);
      expect(result.ayahNumber, 255);
    });

    test('"surah 2 ayah 255" (numeric surah)', () {
      final result = pipeline.process('surah 2 ayah 255');
      expect(result.surahNumber, 2);
      expect(result.ayahNumber, 255);
    });

    test('"surah ikhlas" with no ayah resolves surah only', () {
      final result = pipeline.process('surah ikhlas');
      expect(result.surahNumber, 112);
      expect(result.ayahNumber, isNull);
    });

    test('"explain surah mulk" → explainSurah 67', () {
      final result = pipeline.process('explain surah mulk');
      expect(result.intent, IntentType.explainSurah);
      expect(result.surahNumber, 67);
    });
  });

  // ── Stage 5: Intent detection ──────────────────────────────────────────────

  group('intent detection', () {
    test('"play surah rahman" → playAudio', () {
      final result = pipeline.process('play surah rahman');
      expect(result.intent, IntentType.playAudio);
      expect(result.surahNumber, 55);
    });

    test('"recite surah mulk" → playAudio', () {
      final result = pipeline.process('recite surah mulk');
      expect(result.intent, IntentType.playAudio);
    });

    test('"tafsir 2:255" → tafsir', () {
      final result = pipeline.process('tafsir 2:255');
      expect(result.intent, IntentType.tafsir);
      expect(result.surahNumber, 2);
      expect(result.ayahNumber, 255);
    });

    test('"translate baqarah 1" → translation', () {
      final result = pipeline.process('translate baqarah 1');
      expect(result.intent, IntentType.translation);
      expect(result.surahNumber, 2);
    });

    test('"explain 2:255" → explainAyah', () {
      final result = pipeline.process('explain 2:255');
      expect(result.intent, IntentType.explainAyah);
    });

    test('"explain surah ikhlas" (no ayah) → explainSurah', () {
      final result = pipeline.process('explain surah ikhlas');
      expect(result.intent, IntentType.explainSurah);
      expect(result.surahNumber, 112);
    });

    test('unknown query → askGeneralQuestion', () {
      final result = pipeline.process('what is the meaning of life');
      expect(result.intent, IntentType.askGeneralQuestion);
    });
  });

  // ── Stage 6: Canonical query rewriting ────────────────────────────────────

  group('canonical query rewriting', () {
    test('"surah bakra 255 explain" → canonical explain form', () {
      final result = pipeline.process('surah bakra 255 explain');
      expect(result.canonicalQuery, 'Explain Surah Al-Baqarah verse 255');
    });

    test('"play surah mulk" → canonical recite form', () {
      final result = pipeline.process('play surah mulk');
      expect(result.canonicalQuery, contains('Al-Mulk'));
      expect(result.canonicalQuery.toLowerCase(), contains('recite'));
    });

    test('"tafsir 2:255" → canonical tafsir form', () {
      final result = pipeline.process('tafsir 2:255');
      expect(result.canonicalQuery, 'Tafsir of Surah Al-Baqarah verse 255');
    });

    test('"translate surah ikhlas" → canonical translation form', () {
      final result = pipeline.process('translate surah ikhlas');
      expect(result.canonicalQuery, contains('Translation'));
      expect(result.canonicalQuery, contains('Al-Ikhlas'));
    });

    test('named verse "ayatul kursi" → canonical with verse number', () {
      final result = pipeline.process('ayatul kursi');
      expect(result.canonicalQuery, 'Explain Surah Al-Baqarah verse 255');
    });
  });

  // ── Stage 7: Confidence scoring ───────────────────────────────────────────

  group('confidence scoring and LLM fallback flag', () {
    test('resolved surah → needsLlmFallback false', () {
      final result = pipeline.process('explain surah baqarah');
      expect(result.needsLlmFallback, false);
    });

    test('garbled surah name with intent keyword → needsLlmFallback true', () {
      // "surah xyzzy" (gibberish) with an intent keyword signals low confidence
      final result = pipeline.process('explain surah xyzzy');
      expect(result.needsLlmFallback, true);
    });

    test('general question → needsLlmFallback false', () {
      final result = pipeline.process('what is tawakkul');
      expect(result.needsLlmFallback, false);
    });

    test('named verse → needsLlmFallback always false', () {
      final result = pipeline.process('throne verse');
      expect(result.needsLlmFallback, false);
    });
  });

  // ── Empty / edge cases ─────────────────────────────────────────────────────

  group('edge cases', () {
    test('empty string returns general question with empty cleanText', () {
      final result = pipeline.process('');
      expect(result.cleanText, '');
      expect(result.intent, IntentType.askGeneralQuestion);
      expect(result.needsLlmFallback, false);
    });

    test('whitespace-only string handled gracefully', () {
      final result = pipeline.process('   ');
      expect(result.cleanText, '');
    });

    test('"kul huvallahu ahad meaning" → Al-Ikhlas', () {
      final result = pipeline.process('kul huvallahu ahad meaning');
      expect(result.surahNumber, 112);
    });
  });
}
