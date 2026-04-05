import '../services/vector_store_service.dart' show EmotionalVerse, kEmotionalVerses;

class EmotionalVerseSelector {
  EmotionalVerseSelector._();

  static final RegExp _singleVerseKeyPattern = RegExp(r'^\d{1,3}:\d{1,3}$');
  static final RegExp _tokenPattern = RegExp(r'[a-z0-9]+');

  static const Map<String, _EmotionProfile> _profiles =
      <String, _EmotionProfile>{
        'anxiety': _EmotionProfile(
          categories: <String>{'calm_peace', 'comfort_relief', 'hope_trust'},
          terms: <String>{
            'anxiety',
            'anxious',
            'worry',
            'worried',
            'stress',
            'stressed',
            'overwhelmed',
            'fear',
            'afraid',
            'scared',
            'calm',
            'peace',
            'rest',
            'reassurance',
            'tranquil',
            'heart',
            'relief',
            'trust',
            'safety',
            'protection',
          },
        ),
        'sadness': _EmotionProfile(
          categories: <String>{
            'hope_trust',
            'comfort_relief',
            'mercy_forgiveness',
            'patience_strength',
            'calm_peace',
          },
          terms: <String>{
            'sad',
            'sadness',
            'grief',
            'depressed',
            'depression',
            'hopeless',
            'lost',
            'lonely',
            'alone',
            'comfort',
            'hope',
            'mercy',
            'healing',
            'patience',
            'reassurance',
          },
        ),
        'peace': _EmotionProfile(
          categories: <String>{'calm_peace', 'hope_trust', 'comfort_relief'},
          terms: <String>{
            'peace',
            'calm',
            'serenity',
            'tranquil',
            'tranquility',
            'rest',
            'remembrance',
            'heart',
            'reassurance',
            'contentment',
          },
        ),
        'gratitude': _EmotionProfile(
          categories: <String>{'gratitude_blessings'},
          terms: <String>{
            'grateful',
            'thankful',
            'gratitude',
            'blessing',
            'blessings',
            'favor',
            'favors',
            'increase',
            'abundance',
            'happy',
            'joy',
            'provision',
          },
        ),
        'guidance': _EmotionProfile(
          categories: <String>{
            'hope_trust',
            'patience_strength',
            'calm_peace',
            'comfort_relief',
          },
          terms: <String>{
            'guidance',
            'clarity',
            'wisdom',
            'confused',
            'confusion',
            'path',
            'trust',
            'patience',
            'strength',
            'striving',
          },
        ),
        'difficulty': _EmotionProfile(
          categories: <String>{
            'comfort_relief',
            'hope_trust',
            'calm_peace',
            'patience_strength',
          },
          terms: <String>{
            'difficulty',
            'hardship',
            'relief',
            'comfort',
            'hope',
            'trust',
            'patience',
            'strength',
            'burden',
            'struggle',
          },
        ),
      };

  static List<EmotionalVerse> select({
    required String emotion,
    required String userText,
    int limit = 3,
    List<EmotionalVerse> verses = kEmotionalVerses,
  }) {
    if (limit <= 0) {
      return const <EmotionalVerse>[];
    }

    final profileKey = _canonicalizeEmotion(emotion);
    final profile = _profiles[profileKey] ?? _profiles['difficulty']!;
    final queryTokens = <String>{
      profileKey,
      ...profile.terms,
      ..._tokenize(userText),
      ..._tokenize(emotion),
    };

    final scored = <({EmotionalVerse verse, double score, int index})>[];
    for (var index = 0; index < verses.length; index += 1) {
      final verse = verses[index];
      if (!_singleVerseKeyPattern.hasMatch(verse.verseKey)) {
        continue;
      }

      final metadataTokens = _tokenize(
        '${verse.category.replaceAll('_', ' ')} ${verse.emotion}',
      );
      final translationTokens = _tokenize(verse.translationText);
      final metadataMatches = queryTokens.intersection(metadataTokens).length;
      final translationMatches = queryTokens.intersection(translationTokens).length;
      final profileMatches = profile.terms.intersection(metadataTokens).length;

      final score =
          (profile.categories.contains(verse.category) ? 4.0 : 0.0) +
          (profileMatches * 2.5) +
          (metadataMatches * 1.5) +
          translationMatches.toDouble();
      if (score <= 0) {
        continue;
      }

      scored.add((verse: verse, score: score, index: index));
    }

    scored.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return left.index.compareTo(right.index);
    });

    final selected = <EmotionalVerse>[];
    final seenVerseKeys = <String>{};
    for (final item in scored) {
      if (!seenVerseKeys.add(item.verse.verseKey)) {
        continue;
      }
      selected.add(item.verse);
      if (selected.length >= limit) {
        break;
      }
    }

    if (selected.isNotEmpty) {
      return selected;
    }

    return verses
        .where((verse) => _singleVerseKeyPattern.hasMatch(verse.verseKey))
        .take(limit)
        .toList(growable: false);
  }

  static String _canonicalizeEmotion(String emotion) {
    final normalized = emotion.trim().toLowerCase();
    switch (normalized) {
      case 'anxious':
      case 'anxiety':
      case 'worried':
      case 'worry':
      case 'stress':
      case 'stressed':
      case 'fear':
      case 'afraid':
      case 'scared':
        return 'anxiety';
      case 'sad':
      case 'sadness':
      case 'grief':
      case 'depressed':
      case 'depression':
      case 'hopeless':
      case 'lost':
      case 'lonely':
        return 'sadness';
      case 'peace':
      case 'calm':
      case 'comfort':
      case 'serenity':
      case 'reassurance':
        return 'peace';
      case 'grateful':
      case 'thankful':
      case 'gratitude':
      case 'happy':
        return 'gratitude';
      case 'confused':
      case 'angry':
        return 'guidance';
      default:
        return normalized.isEmpty ? 'difficulty' : normalized;
    }
  }

  static Set<String> _tokenize(String text) {
    return _tokenPattern
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0) ?? '')
        .where((token) => token.length >= 3)
        .toSet();
  }
}

class _EmotionProfile {
  const _EmotionProfile({required this.categories, required this.terms});

  final Set<String> categories;
  final Set<String> terms;
}