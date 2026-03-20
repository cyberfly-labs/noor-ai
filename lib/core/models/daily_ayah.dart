class DailyAyah {
  final String id;
  final String verseKey;
  final String? arabicText;
  final String? translationText;
  final String? explanation;
  final String date; // 'YYYY-MM-DD'

  const DailyAyah({
    required this.id,
    required this.verseKey,
    this.arabicText,
    this.translationText,
    this.explanation,
    required this.date,
  });

  factory DailyAyah.fromDb(Map<String, dynamic> map) {
    return DailyAyah(
      id: map['id'] as String,
      verseKey: map['verse_key'] as String,
      arabicText: map['arabic_text'] as String?,
      translationText: map['translation_text'] as String?,
      explanation: map['explanation'] as String?,
      date: map['date'] as String,
    );
  }

  Map<String, dynamic> toDb() => {
    'id': id,
    'verse_key': verseKey,
    'arabic_text': arabicText,
    'translation_text': translationText,
    'explanation': explanation,
    'date': date,
  };
}
