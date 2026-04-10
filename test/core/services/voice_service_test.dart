import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/core/services/voice_service.dart';

void main() {
  group('normalizeSpokenTextForTts', () {
    test('preserves structure and expands Quran references for speech', () {
      final normalized = normalizeSpokenTextForTts('''
## Guidance

- Remember **2:286**.
- Reflect on 94:5-6.
- Read [this note](https://example.com) and `ignore_code`.
''');

      expect(
        normalized,
        'Guidance. Remember Surah 2, ayah 286. Reflect on Surah 94, ayahs 5 to 6. Read this note and ignore code.',
      );
    });

    test('keeps invalid colon numbers untouched', () {
      final normalized = normalizeSpokenTextForTts(
        'This is not a Quran citation: 999:999.',
      );

      expect(normalized, 'This is not a Quran citation: 999:999.');
    });
  });

  group('buildSpeechChunksForTts', () {
    test('keeps multi-sentence text together when under the limit', () {
      final chunks = buildSpeechChunksForTts(
        'First sentence. Second sentence. Third sentence.',
        maxChunkLength: 80,
      );

      expect(chunks, <String>[
        'First sentence. Second sentence. Third sentence.',
      ]);
    });

    test('prefers punctuation boundaries for long chunks', () {
      final text =
          'This opening thought is intentionally long enough to push the chunk near the boundary, and it should still break cleanly at a comma instead of chopping straight through the middle of a phrase when the spoken response is prepared for playback.';

      final chunks = buildSpeechChunksForTts(text, maxChunkLength: 120);

      expect(chunks.length, greaterThan(1));
      expect(chunks.first.endsWith(','), isTrue);
      expect(chunks.every((chunk) => chunk.length <= 120), isTrue);
      expect(chunks.join(' '), text);
    });
  });
}
