class QuranTafsirResource {
  const QuranTafsirResource({
    required this.id,
    required this.name,
    required this.authorName,
    required this.languageName,
    required this.translatedName,
    required this.slug,
  });

  final int id;
  final String name;
  final String authorName;
  final String languageName;
  final String translatedName;
  final String slug;

  factory QuranTafsirResource.fromJson(Map<String, dynamic> json) {
    final translatedName = json['translated_name'] as Map<String, dynamic>?;

    return QuranTafsirResource(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      authorName: json['author_name'] as String? ?? '',
      languageName: json['language_name'] as String? ?? '',
      translatedName: translatedName?['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
    );
  }

  String get displayName {
    if (translatedName.trim().isNotEmpty) {
      return translatedName.trim();
    }
    return name.trim();
  }

  bool get isEnglish {
    final haystack = [
      languageName,
      translatedName,
      name,
      slug,
    ].join(' ').toLowerCase();

    return haystack.contains('english') ||
        RegExp(r'\ben\b', caseSensitive: false).hasMatch(haystack);
  }

  int get englishPreferenceScore {
    var score = 0;
    final normalizedLanguage = languageName.trim().toLowerCase();
    final normalizedTranslated = translatedName.trim().toLowerCase();
    final normalizedName = name.trim().toLowerCase();
    final normalizedSlug = slug.trim().toLowerCase();

    if (normalizedLanguage == 'english') {
      score += 100;
    } else if (normalizedLanguage.contains('english')) {
      score += 80;
    }

    if (normalizedTranslated.contains('english')) {
      score += 50;
    }
    if (normalizedName.contains('english')) {
      score += 40;
    }
    if (RegExp(r'(^|[-_])en($|[-_])').hasMatch(normalizedSlug)) {
      score += 20;
    }

    return score;
  }
}