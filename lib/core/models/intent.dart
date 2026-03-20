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

  const Intent({
    required this.type,
    this.surahNumber,
    this.ayahNumber,
    this.emotion,
    required this.rawText,
  });

  String? get verseKey {
    if (surahNumber != null && ayahNumber != null) {
      return '$surahNumber:$ayahNumber';
    }
    return null;
  }

  @override
  String toString() => 'Intent($type, surah=$surahNumber, ayah=$ayahNumber, emotion=$emotion)';
}
