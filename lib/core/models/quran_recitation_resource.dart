class QuranRecitationResource {
  const QuranRecitationResource({
    required this.id,
    required this.reciterName,
    required this.style,
    required this.translatedName,
  });

  final int id;
  final String reciterName;
  final String style;
  final String translatedName;

  factory QuranRecitationResource.fromJson(Map<String, dynamic> json) {
    final translatedName = json['translated_name'] as Map<String, dynamic>?;

    return QuranRecitationResource(
      id: json['id'] as int? ?? 0,
      reciterName: json['reciter_name'] as String? ?? '',
      style: json['style'] as String? ?? '',
      translatedName: translatedName?['name'] as String? ?? '',
    );
  }

  String get displayName {
    if (translatedName.trim().isNotEmpty) {
      return translatedName.trim();
    }
    return reciterName.trim();
  }

  String get subtitle {
    final parts = <String>[];
    if (reciterName.trim().isNotEmpty &&
        reciterName.trim().toLowerCase() != displayName.toLowerCase()) {
      parts.add(reciterName.trim());
    }
    if (style.trim().isNotEmpty) {
      parts.add(style.trim());
    }
    return parts.join(' • ');
  }
}