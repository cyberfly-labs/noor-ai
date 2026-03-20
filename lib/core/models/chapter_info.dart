class ChapterInfo {
  const ChapterInfo({
    required this.id,
    required this.chapterId,
    required this.languageName,
    required this.shortText,
    required this.source,
    required this.text,
  });

  final int id;
  final int chapterId;
  final String languageName;
  final String shortText;
  final String source;
  final String text;

  factory ChapterInfo.fromJson(Map<String, dynamic> json) {
    return ChapterInfo(
      id: json['id'] as int? ?? 0,
      chapterId: json['chapter_id'] as int? ?? 0,
      languageName: json['language_name'] as String? ?? '',
      shortText: json['short_text'] as String? ?? '',
      source: json['source'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}