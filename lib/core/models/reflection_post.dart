/// A Quran Reflect post (lesson or reflection) from the community feed.
class ReflectionPost {
  final int id;
  final String? title;
  final String body;
  final String? kind; // "reflection" or "lesson"
  final String? authorName;
  final String? authorUsername;
  final String? authorAvatarUrl;
  final int likesCount;
  final int commentsCount;
  final List<String> verseKeys;
  final String? createdAt;
  final String? url;

  const ReflectionPost({
    required this.id,
    required this.body,
    this.title,
    this.kind,
    this.authorName,
    this.authorUsername,
    this.authorAvatarUrl,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.verseKeys = const [],
    this.createdAt,
    this.url,
  });

  factory ReflectionPost.fromJson(Map<String, dynamic> json) {
    final user = json['user'] ?? json['author'] ?? json['profile'];
    final userMap = user is Map ? user.cast<String, dynamic>() : null;

    final rawVerses = json['verses'] ?? json['verse_keys'] ?? const [];
    final verseKeys = <String>[];
    if (rawVerses is List) {
      for (final v in rawVerses) {
        if (v is String) {
          verseKeys.add(v);
        } else if (v is Map) {
          final key = v['verse_key'] ?? v['key'];
          if (key is String) verseKeys.add(key);
        }
      }
    }

    String? strOrNull(dynamic v) => v is String && v.isNotEmpty ? v : null;

    return ReflectionPost(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: strOrNull(json['title']),
      body: (json['body'] ?? json['content'] ?? json['text'] ?? '').toString(),
      kind: strOrNull(json['kind'] ?? json['type']),
      authorName: strOrNull(userMap?['name'] ?? userMap?['full_name']),
      authorUsername: strOrNull(userMap?['username'] ?? userMap?['handle']),
      authorAvatarUrl: strOrNull(
          userMap?['avatar_url'] ?? userMap?['profile_picture']),
      likesCount: (json['likes_count'] as num?)?.toInt() ??
          (json['reactions_count'] as num?)?.toInt() ??
          0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      verseKeys: verseKeys,
      createdAt: strOrNull(json['created_at'] ?? json['published_at']),
      url: strOrNull(json['url'] ?? json['permalink']),
    );
  }
}
