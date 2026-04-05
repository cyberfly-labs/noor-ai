import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/core/utils/emotional_verse_selector.dart';

void main() {
  group('EmotionalVerseSelector', () {
    test('anxious prompts prefer calming curated verses', () {
      final selected = EmotionalVerseSelector.select(
        emotion: 'anxious',
        userText: 'I feel anxious',
        limit: 3,
      );

      final verseKeys = selected.map((verse) => verse.verseKey).toList();
      expect(verseKeys, contains('13:28'));
      expect(verseKeys, isNot(contains('94:7-8')));
    });

    test('gratitude prompts prioritize gratitude verses', () {
      final selected = EmotionalVerseSelector.select(
        emotion: 'grateful',
        userText: 'I feel grateful today',
        limit: 3,
      );

      expect(selected, isNotEmpty);
      expect(selected.first.category, 'gratitude_blessings');
    });

    test('selection only returns single verse keys for clickable citations', () {
      final selected = EmotionalVerseSelector.select(
        emotion: 'peace',
        userText: 'I need calm and peace',
        limit: 5,
      );

      expect(
        selected.every((verse) => RegExp(r'^\d{1,3}:\d{1,3}$').hasMatch(verse.verseKey)),
        isTrue,
      );
    });
  });
}