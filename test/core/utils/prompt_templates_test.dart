import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/core/utils/prompt_templates.dart';

void main() {
  group('PromptTemplates.dailyAyahExplanation', () {
    test('includes verse key and avoids old scaffold placeholders', () {
      final prompt = PromptTemplates.dailyAyahExplanation(
        verseKey: '102:8',
        arabicText: 'ثُمَّ لَتُسْـَٔلُنَّ يَوْمَئِذٍ عَنِ النَّعِيمِ',
        translationText:
            'Then you will surely be asked that Day about pleasure.',
        tafsirText: 'This verse warns that people will be questioned about blessings.',
        tafsirSource: 'Local English Tafsir',
      );

      expect(prompt, contains('102:8'));
      expect(prompt, contains('Return only the explanation.'));
      expect(prompt, isNot(contains('[Quote the verse and reference.]')));
      expect(
        prompt,
        isNot(contains('[Grounded explanation in 4-6 sentences. Each sentence must add new information.]')),
      );
      expect(prompt, isNot(contains('[1 short takeaway sentence.]')));
    });
  });

  group('PromptTemplates.speed-oriented grounded prompts', () {
    test('emotional prompt no longer asks model to emit Quran section', () {
      final prompt = PromptTemplates.emotionalGuidance(
        emotion: 'anxiety',
        userText: 'I feel anxious',
        verseReferences: const <String>['13:28', '2:286'],
        verseTranslations: const <String>[
          'Verily, in the remembrance of Allah do hearts find rest.',
          'Allah does not burden a soul beyond that it can bear.',
        ],
      );

      expect(prompt, contains('The Quran quotes are shown separately in the UI'));
      expect(prompt, isNot(contains('📖 Quran:')));
    });

    test('grounded general prompt omits prefilled Quran slot output', () {
      final prompt = PromptTemplates.groundedGeneralQuestion(
        question: 'How do I handle anxiety?',
        retrievalQuery: 'anxiety calm trust',
        evidenceBlocks: const <String>[
          '[QURAN]\nSurah: 13:28\nTranslation: Verily, in the remembrance of Allah do hearts find rest.',
        ],
        verseReferences: const <String>['13:28'],
        verseTranslations: const <String>[
          'Verily, in the remembrance of Allah do hearts find rest.',
        ],
      );

      expect(prompt, contains('The Quran quotes are shown separately in the UI'));
      expect(prompt, isNot(contains('📖 Quran:')));
    });
  });
}