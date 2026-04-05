import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/core/utils/emotional_response_repair.dart';

void main() {
  group('EmotionalResponseRepair', () {
    test('rebuilds broken quote echo emotional responses', () {
      const response = '''📚 Explanation:
- 13:28: "Verily, in the remembrance of Allah do hearts find rest."

🤍 Comfort:
- 2:286: "Allah does not burden a soul beyond that it can bear."

✨ Summary:
- 13:28: "Verily, in the remembrance of Allah do hearts find rest."''';

      final repaired = EmotionalResponseRepair.repairIfNeeded(
        response: response,
        emotion: 'anxious',
        citations: const <EmotionalResponseCitation>[
          EmotionalResponseCitation(
            verseKey: '13:28',
            excerpt: 'Verily, in the remembrance of Allah do hearts find rest.',
          ),
          EmotionalResponseCitation(
            verseKey: '2:286',
            excerpt: 'Allah does not burden a soul beyond that it can bear.',
          ),
        ],
      );

      expect(repaired, contains('📖 Quran:'));
      expect(repaired, contains('📚 Explanation:'));
      expect(repaired, contains('🤍 Comfort:'));
      expect(repaired, contains('✨ Summary:'));
      expect(repaired, contains('13:28'));
      expect(repaired, contains('2:286'));
      expect(repaired, contains('this anxious moment'));
      expect(repaired, isNot(equals(response.trim())));
    });

    test('keeps already good emotional prose unchanged', () {
      const response = '''📖 Quran:
- 13:28: "Verily, in the remembrance of Allah do hearts find rest."

📚 Explanation:
- 13:28: This verse points you toward calm through the remembrance of Allah, showing where the heart can settle.

🤍 Comfort:
Your fear is real, but Allah has not left you without guidance or relief.

✨ Summary:
Return to remembrance and trust that Allah can steady your heart.''';

      final repaired = EmotionalResponseRepair.repairIfNeeded(
        response: response,
        emotion: 'anxious',
        citations: const <EmotionalResponseCitation>[
          EmotionalResponseCitation(
            verseKey: '13:28',
            excerpt: 'Verily, in the remembrance of Allah do hearts find rest.',
          ),
        ],
      );

      expect(repaired, equals(response.trim()));
    });
  });
}
