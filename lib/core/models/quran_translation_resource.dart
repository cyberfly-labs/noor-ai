class QuranTranslationResource {
  const QuranTranslationResource({
    required this.id,
    required this.name,
    required this.authorName,
    required this.languageName,
    required this.translatedName,
  });

  final int id;
  final String name;
  final String authorName;
  final String languageName;
  final String translatedName;

  factory QuranTranslationResource.fromJson(Map<String, dynamic> json) {
    final translatedName = json['translated_name'] as Map<String, dynamic>?;

    return QuranTranslationResource(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      authorName: json['author_name'] as String? ?? '',
      languageName: json['language_name'] as String? ?? '',
      translatedName: translatedName?['name'] as String? ?? '',
    );
  }

  String get displayName {
    if (translatedName.trim().isNotEmpty) {
      return translatedName.trim();
    }
    return name.trim();
  }

  String get subtitle {
    final parts = <String>[];
    if (authorName.trim().isNotEmpty) {
      parts.add(authorName.trim());
    }
    if (languageName.trim().isNotEmpty) {
      parts.add(languageName.trim());
    }
    return parts.join(' • ');
  }
}