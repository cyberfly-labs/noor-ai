class Verse {
  final String verseKey;
  final int surahNumber;
  final int ayahNumber;
  final String? arabicText;
  final String? translationText;
  final String? transliteration;
  final String? audioUrl;

  const Verse({
    required this.verseKey,
    required this.surahNumber,
    required this.ayahNumber,
    this.arabicText,
    this.translationText,
    this.transliteration,
    this.audioUrl,
  });

  factory Verse.fromApiJson(Map<String, dynamic> json) {
    final verse = json['verse'] as Map<String, dynamic>? ?? json;
    final translations = json['translations'] as List?;
    final audio = json['audio'] as Map<String, dynamic>?;

    return Verse(
      verseKey: verse['verse_key'] as String? ?? '${verse['chapter_id']}:${verse['verse_number']}',
      surahNumber: verse['chapter_id'] as int? ?? 0,
      ayahNumber: verse['verse_number'] as int? ?? 0,
      arabicText: verse['text_uthmani'] as String? ?? verse['text'] as String?,
      translationText: translations != null && translations.isNotEmpty
          ? translations.first['text'] as String?
          : null,
      audioUrl: audio?['url'] as String?,
    );
  }

  factory Verse.fromAlQuranCloud(Map<String, dynamic> json) {
    final surah = json['surah'] as Map<String, dynamic>?;

    return Verse(
      verseKey: '${surah?['number'] ?? 0}:${json['numberInSurah'] ?? 0}',
      surahNumber: surah?['number'] as int? ?? 0,
      ayahNumber: json['numberInSurah'] as int? ?? 0,
      arabicText: json['text'] as String?,
      translationText: json['text'] as String?,
      audioUrl: json['audio'] as String?,
    );
  }

  factory Verse.fromDb(Map<String, dynamic> map) {
    return Verse(
      verseKey: map['verse_key'] as String,
      surahNumber: map['surah_number'] as int,
      ayahNumber: map['ayah_number'] as int,
      arabicText: map['arabic_text'] as String?,
      translationText: map['translation_text'] as String?,
      audioUrl: map['audio_url'] as String?,
    );
  }

  Map<String, dynamic> toDb() => {
    'verse_key': verseKey,
    'surah_number': surahNumber,
    'ayah_number': ayahNumber,
    'arabic_text': arabicText,
    'translation_text': translationText,
    'audio_url': audioUrl,
  };
}
