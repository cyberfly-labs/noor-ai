/// Juz (Para) metadata.
class JuzInfo {
  final int id;
  final int juzNumber;
  final int versesCount;
  final int? firstVerseId;
  final int? lastVerseId;
  final String? firstVerseKey;
  final String? lastVerseKey;

  /// Map of surah number (as string) → ayah range (e.g. "1-141").
  final Map<String, String> verseMapping;

  const JuzInfo({
    required this.id,
    required this.juzNumber,
    required this.versesCount,
    this.firstVerseId,
    this.lastVerseId,
    this.firstVerseKey,
    this.lastVerseKey,
    this.verseMapping = const {},
  });

  factory JuzInfo.fromJson(Map<String, dynamic> json) {
    final rawMapping = json['verse_mapping'];
    final mapping = <String, String>{};
    if (rawMapping is Map) {
      rawMapping.forEach((k, v) {
        if (v != null) mapping[k.toString()] = v.toString();
      });
    }
    return JuzInfo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      juzNumber: (json['juz_number'] as num?)?.toInt() ?? 0,
      versesCount: (json['verses_count'] as num?)?.toInt() ?? 0,
      firstVerseId: (json['first_verse_id'] as num?)?.toInt(),
      lastVerseId: (json['last_verse_id'] as num?)?.toInt(),
      firstVerseKey: json['first_verse_key'] as String?,
      lastVerseKey: json['last_verse_key'] as String?,
      verseMapping: mapping,
    );
  }
}
