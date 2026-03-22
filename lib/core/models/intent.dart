enum IntentType {
  explainSurah,
  explainAyah,
  playAudio,
  translation,
  tafsir,
  emotionalGuidance,
  askGeneralQuestion,
}

class Intent {
  final IntentType type;
  final int? surahNumber;
  final int? ayahNumber;
  final String? emotion;
  final String rawText;

  /// Always an English query optimised for vector-DB retrieval.
  /// Defaults to [rawText] when not explicitly set (typed-input path).
  final String retrievalQuery;

  /// BCP-47-style language hint for the response ('en', 'ar', 'ta', 'hi').
  /// The LLM already detects language from [rawText]; this is an explicit hint.
  final String responseLanguage;

  const Intent({
    required this.type,
    this.surahNumber,
    this.ayahNumber,
    this.emotion,
    required this.rawText,
    String? retrievalQuery,
    this.responseLanguage = 'en',
  }) : retrievalQuery = retrievalQuery ?? rawText;

  String? get verseKey {
    if (surahNumber != null && ayahNumber != null) {
      return '$surahNumber:$ayahNumber';
    }
    return null;
  }

  @override
  String toString() => 'Intent($type, surah=$surahNumber, ayah=$ayahNumber, emotion=$emotion, lang=$responseLanguage)';
}
