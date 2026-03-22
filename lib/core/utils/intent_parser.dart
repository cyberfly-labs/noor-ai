import '../models/intent.dart';
import '../models/surah.dart';
import 'named_verse_registry.dart';
import 'quran_query_helpers.dart';

/// Rule-based intent parser with LLM fallback for unmatched queries.
class IntentParser {
  IntentParser._();
  static final IntentParser instance = IntentParser._();

  static const Map<String, String> _shortEmotionHints = <String, String>{
    'peace': 'peace',
    'inner peace': 'peace',
    'calm': 'peace',
    'serenity': 'peace',
    'tranquility': 'peace',
    'tranquillity': 'peace',
    'comfort': 'peace',
    'reassurance': 'peace',
  };

  static const Map<String, String> _emotionPhraseHints = <String, String>{
    'peace of mind': 'anxiety',
    'lost my peace': 'anxiety',
    'peace is gone': 'anxiety',
    'heart feels heavy': 'sadness',
    'heavy heart': 'sadness',
    'feel empty': 'sadness',
    'feeling empty': 'sadness',
    'feel numb': 'sadness',
    'feeling numb': 'sadness',
    'feel overwhelmed': 'stress',
    'feeling overwhelmed': 'stress',
    'overwhelmed by life': 'stress',
    'restless': 'anxiety',
    'can\'t calm down': 'anxiety',
    'cannot calm down': 'anxiety',
    'can\'t focus': 'confusion',
    'cannot focus': 'confusion',
    'feel lost': 'lost',
    'feeling lost': 'lost',
    'i am lost': 'lost',
    'i\'m lost': 'lost',
    'alone in this': 'lonely',
    'feel alone': 'lonely',
    'feeling alone': 'lonely',
    'feel lonely': 'lonely',
    'feeling lonely': 'lonely',
    'give up': 'hopeless',
    'no hope': 'hopeless',
    'lost hope': 'hopeless',
    'feel hopeless': 'hopeless',
    'feeling hopeless': 'hopeless',
  };

  static final _explainSurahPattern = RegExp(
    r'\b(?:explain|about|tell me about|what is|meaning of)\s+(?:surah?\s+)?(.+)',
    caseSensitive: false,
  );

  static final _explainAyahPattern = RegExp(
    r'\b(?:explain|meaning of|what does)\s+(?:ayah?|verse)\s+(\d+)[:\s]+(\d+)',
    caseSensitive: false,
  );

  static final _explainNamedAyahPattern = RegExp(
    r'\b(?:explain|meaning of|what does)\s+(?:ayah?|verse)\s+(\d+)\s+(?:of\s+)?(?:surah\s+)?([a-z\- ]+)',
    caseSensitive: false,
  );

  static final _explainSurahAyahPattern = RegExp(
    r'\b(?:explain|meaning of|what does)\s+(?:surah\s+)?([a-z\- ]+)\s+(?:ayah?|verse)\s+(\d+)',
    caseSensitive: false,
  );

  static final _explainVerseKeyPattern = RegExp(
    r'\b(?:explain|meaning|about)\s+(\d{1,3}):(\d{1,3})\b',
    caseSensitive: false,
  );

  static final _playPattern = RegExp(
    r'\b(?:play|recite|read aloud|listen to)\s+(?:surah?\s+)?(.+)',
    caseSensitive: false,
  );

  static final _translatePattern = RegExp(
    r'\b(?:translate|translation of)\s+(?:ayah?|verse|surah?)?\s*(\d+)[:\s]+(\d+)',
    caseSensitive: false,
  );

  static final _translateNamedAyahPattern = RegExp(
    r'\b(?:translate|translation of)\s+(?:ayah?|verse)\s+(\d+)\s+(?:of\s+)?(?:surah\s+)?([a-z\- ]+)',
    caseSensitive: false,
  );

  static final _translateSurahAyahPattern = RegExp(
    r'\b(?:translate|translation of)\s+(?:surah\s+)?([a-z\- ]+)\s+(?:ayah?|verse)\s+(\d+)',
    caseSensitive: false,
  );

  static final _tafsirPattern = RegExp(
    r'\b(?:tafsir|tafseer|exegesis|commentary)\s+(?:of\s+)?(?:ayah?|verse|surah?)?\s*(\d+)[:\s]+(\d+)',
    caseSensitive: false,
  );

  static final _tafsirNamedAyahPattern = RegExp(
    r'\b(?:tafsir|tafseer|exegesis|commentary)\s+(?:of\s+)?(?:ayah?|verse)\s+(\d+)\s+(?:of\s+)?(?:surah\s+)?([a-z\- ]+)',
    caseSensitive: false,
  );

  static final _tafsirSurahAyahPattern = RegExp(
    r'\b(?:tafsir|tafseer|exegesis|commentary)\s+(?:of\s+)?(?:surah\s+)?([a-z\- ]+)\s+(?:ayah?|verse)\s+(\d+)',
    caseSensitive: false,
  );

  static final _emotionPattern = RegExp(
    r'\b(?:i\s+(?:feel|am|m)\s+(?:feeling\s+)?)(sad|anxious|worried|scared|angry|lonely|lost|depressed|hopeless|stressed|grateful|thankful|happy|confused|afraid)\b',
    caseSensitive: false,
  );

  static final _emotionAltPattern = RegExp(
    r'\b(anxiety|sadness|grief|fear|anger|loneliness|depression|stress|worry|hope|patience|gratitude)\b',
    caseSensitive: false,
  );

  /// Parse user text into an Intent, enriched with an English [retrievalQuery]
  /// and detected [responseLanguage].
  Intent parse(String text) {
    final raw = _parseInternal(text);
    final retrievalQuery = QuranQueryHelpers.buildEnglishRetrievalQuery(
      correctedText: raw.rawText.toLowerCase(),
      intent: raw.type,
      surahNumber: raw.surahNumber,
      ayahNumber: raw.ayahNumber,
    );
    final responseLanguage = QuranQueryHelpers.detectResponseLanguage(text);
    return Intent(
      type: raw.type,
      surahNumber: raw.surahNumber,
      ayahNumber: raw.ayahNumber,
      emotion: raw.emotion,
      rawText: raw.rawText,
      retrievalQuery: retrievalQuery,
      responseLanguage: responseLanguage,
    );
  }

  /// Internal parse — returns an unenriched Intent without retrievalQuery/lang.
  Intent _parseInternal(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return Intent(type: IntentType.askGeneralQuestion, rawText: trimmed);
    }

    final normalized = trimmed.toLowerCase();

    // ── Named verse/surah aliases (highest priority before emotion checks) ──
    final namedRef = namedVerseMap[normalized];
    if (namedRef != null) {
      if (namedRef.ayah != null) {
        return Intent(
          type: IntentType.explainAyah,
          surahNumber: namedRef.surah,
          ayahNumber: namedRef.ayah,
          rawText: trimmed,
        );
      } else {
        return Intent(
          type: IntentType.explainSurah,
          surahNumber: namedRef.surah,
          rawText: trimmed,
        );
      }
    }
    // Also check if the query contains a named verse phrase
    for (final entry in namedVerseMap.entries) {
      if (normalized.contains(entry.key)) {
        final ref = entry.value;
        if (ref.ayah != null) {
          return Intent(
            type: IntentType.explainAyah,
            surahNumber: ref.surah,
            ayahNumber: ref.ayah,
            rawText: trimmed,
          );
        } else {
          return Intent(
            type: IntentType.explainSurah,
            surahNumber: ref.surah,
            rawText: trimmed,
          );
        }
      }
    }
    final emotionMatch = _emotionPattern.firstMatch(trimmed);
    if (emotionMatch != null) {
      return Intent(
        type: IntentType.emotionalGuidance,
        emotion: emotionMatch.group(1)?.toLowerCase(),
        rawText: trimmed,
      );
    }

    final phraseEmotion = _emotionFromPhrase(normalized);
    if (phraseEmotion != null) {
      return Intent(
        type: IntentType.emotionalGuidance,
        emotion: phraseEmotion,
        rawText: trimmed,
      );
    }

    final shortEmotion = _emotionFromShortText(normalized);
    if (shortEmotion != null) {
      return Intent(
        type: IntentType.emotionalGuidance,
        emotion: shortEmotion,
        rawText: trimmed,
      );
    }

    final emotionAltMatch = _emotionAltPattern.firstMatch(trimmed);
    if (emotionAltMatch != null) {
      return Intent(
        type: IntentType.emotionalGuidance,
        emotion: emotionAltMatch.group(1)?.toLowerCase(),
        rawText: trimmed,
      );
    }

    // Check tafsir
    final tafsirMatch = _tafsirPattern.firstMatch(trimmed);
    if (tafsirMatch != null) {
      return Intent(
        type: IntentType.tafsir,
        surahNumber: int.tryParse(tafsirMatch.group(1) ?? ''),
        ayahNumber: int.tryParse(tafsirMatch.group(2) ?? ''),
        rawText: trimmed,
      );
    }

    final tafsirNamedAyah = _parseNamedAyahIntent(
      trimmed,
      pattern: _tafsirNamedAyahPattern,
      type: IntentType.tafsir,
    );
    if (tafsirNamedAyah != null) {
      return tafsirNamedAyah;
    }

    final tafsirSurahAyah = _parseSurahAyahIntent(
      trimmed,
      pattern: _tafsirSurahAyahPattern,
      type: IntentType.tafsir,
    );
    if (tafsirSurahAyah != null) {
      return tafsirSurahAyah;
    }

    // Check translate
    final translateMatch = _translatePattern.firstMatch(trimmed);
    if (translateMatch != null) {
      return Intent(
        type: IntentType.translation,
        surahNumber: int.tryParse(translateMatch.group(1) ?? ''),
        ayahNumber: int.tryParse(translateMatch.group(2) ?? ''),
        rawText: trimmed,
      );
    }

    final translateNamedAyah = _parseNamedAyahIntent(
      trimmed,
      pattern: _translateNamedAyahPattern,
      type: IntentType.translation,
    );
    if (translateNamedAyah != null) {
      return translateNamedAyah;
    }

    final translateSurahAyah = _parseSurahAyahIntent(
      trimmed,
      pattern: _translateSurahAyahPattern,
      type: IntentType.translation,
    );
    if (translateSurahAyah != null) {
      return translateSurahAyah;
    }

    // Check play/recite
    final playMatch = _playPattern.firstMatch(trimmed);
    if (playMatch != null) {
      final target = playMatch.group(1)?.trim() ?? '';
      final surahNum = _parseSurahReference(target);
      if (surahNum != null) {
        return Intent(
          type: IntentType.playAudio,
          surahNumber: surahNum,
          rawText: trimmed,
        );
      }
    }

    // Check explain ayah with verse key (e.g., "explain 2:255")
    final verseKeyMatch = _explainVerseKeyPattern.firstMatch(trimmed);
    if (verseKeyMatch != null) {
      return Intent(
        type: IntentType.explainAyah,
        surahNumber: int.tryParse(verseKeyMatch.group(1) ?? ''),
        ayahNumber: int.tryParse(verseKeyMatch.group(2) ?? ''),
        rawText: trimmed,
      );
    }

    // Check explain ayah (e.g., "explain ayah 2:255")
    final ayahMatch = _explainAyahPattern.firstMatch(trimmed);
    if (ayahMatch != null) {
      return Intent(
        type: IntentType.explainAyah,
        surahNumber: int.tryParse(ayahMatch.group(1) ?? ''),
        ayahNumber: int.tryParse(ayahMatch.group(2) ?? ''),
        rawText: trimmed,
      );
    }

    final explainNamedAyah = _parseNamedAyahIntent(
      trimmed,
      pattern: _explainNamedAyahPattern,
      type: IntentType.explainAyah,
    );
    if (explainNamedAyah != null) {
      return explainNamedAyah;
    }

    final explainSurahAyah = _parseSurahAyahIntent(
      trimmed,
      pattern: _explainSurahAyahPattern,
      type: IntentType.explainAyah,
    );
    if (explainSurahAyah != null) {
      return explainSurahAyah;
    }

    // Check explain surah
    final surahMatch = _explainSurahPattern.firstMatch(trimmed);
    if (surahMatch != null) {
      final target = surahMatch.group(1)?.trim() ?? '';
      final surahNum = _parseSurahReference(target);
      if (surahNum != null) {
        return Intent(
          type: IntentType.explainSurah,
          surahNumber: surahNum,
          rawText: trimmed,
        );
      }
    }

    // Default: general question
    return Intent(type: IntentType.askGeneralQuestion, rawText: trimmed);
  }

  String? _emotionFromPhrase(String text) {
    for (final entry in _emotionPhraseHints.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _emotionFromShortText(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return null;
    }

    if (_shortEmotionHints.containsKey(normalized)) {
      return _shortEmotionHints[normalized];
    }

    final words = normalized.split(RegExp(r'\s+'));
    if (words.length > 3) {
      return null;
    }

    for (final entry in _shortEmotionHints.entries) {
      if (normalized == 'need ${entry.key}' ||
          normalized == 'want ${entry.key}' ||
          normalized == 'find ${entry.key}' ||
          normalized == 'seeking ${entry.key}') {
        return entry.value;
      }
    }

    return null;
  }

  /// Try to parse a surah reference (name or number)
  int? _parseSurahReference(String text) {
    // Try direct number
    final num = int.tryParse(text);
    if (num != null && num >= 1 && num <= 114) return num;

    // Try surah name lookup
    return SurahLookup.findSurahNumber(text);
  }

  Intent? _parseNamedAyahIntent(
    String text, {
    required RegExp pattern,
    required IntentType type,
  }) {
    final match = pattern.firstMatch(text);
    if (match == null) {
      return null;
    }

    final ayahNumber = int.tryParse(match.group(1) ?? '');
    final surahNumber = _parseSurahReference(match.group(2) ?? '');
    if (surahNumber == null || ayahNumber == null) {
      return null;
    }

    return Intent(
      type: type,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      rawText: text,
    );
  }

  Intent? _parseSurahAyahIntent(
    String text, {
    required RegExp pattern,
    required IntentType type,
  }) {
    final match = pattern.firstMatch(text);
    if (match == null) {
      return null;
    }

    final surahNumber = _parseSurahReference(match.group(1) ?? '');
    final ayahNumber = int.tryParse(match.group(2) ?? '');
    if (surahNumber == null || ayahNumber == null) {
      return null;
    }

    return Intent(
      type: type,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      rawText: text,
    );
  }

  /// Generate an LLM classification prompt for ambiguous queries
  String classificationPrompt(String userText) {
    return '''Classify this Quran-related query into exactly one category.

Categories:
- explain_surah: User wants explanation of a surah
- explain_ayah: User wants explanation of a specific verse
- play_audio: User wants to listen to recitation
- translation: User wants translation of a verse
- tafsir: User wants tafsir/commentary
- emotional_guidance: User is expressing emotions and needs comfort from Quran
- ask_general_question: General question about Islam/Quran

Query: "$userText"

Respond with ONLY the category name, nothing else.''';
  }
}
