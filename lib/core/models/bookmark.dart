class Bookmark {
  final String id;
  final String verseKey;
  final String? surahName;
  final String? arabicText;
  final String? translationText;
  final String? note;
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.verseKey,
    this.surahName,
    this.arabicText,
    this.translationText,
    this.note,
    required this.createdAt,
  });

  factory Bookmark.fromDb(Map<String, dynamic> map) {
    return Bookmark(
      id: map['id'] as String,
      verseKey: map['verse_key'] as String,
      surahName: map['surah_name'] as String?,
      arabicText: map['arabic_text'] as String?,
      translationText: map['translation_text'] as String?,
      note: map['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toDb() => {
    'id': id,
    'verse_key': verseKey,
    'surah_name': surahName,
    'arabic_text': arabicText,
    'translation_text': translationText,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}
