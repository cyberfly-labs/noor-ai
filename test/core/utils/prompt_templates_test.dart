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
}