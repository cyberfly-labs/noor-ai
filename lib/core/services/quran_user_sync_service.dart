import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/bookmark.dart';
import '../models/verse.dart';
import 'database_service.dart';
import 'quran_api_config_service.dart';
import 'quran_user_session_service.dart';

@visibleForTesting
Map<String, dynamic> buildQuranReflectPostPayload({
  required String body,
  required List<String> verseKeys,
  DateTime? publishedAt,
}) {
  final references = verseKeys
      .map((key) => key.trim())
      .where((key) => key.contains(':'))
      .map((key) {
        final parts = key.split(':');
        final chapterId = int.tryParse(parts.first) ?? 0;
        final ayah = int.tryParse(parts.last) ?? 0;
        return <String, dynamic>{
          'chapterId': chapterId,
          'from': ayah,
          'to': ayah,
        };
      })
      .where((ref) => (ref['chapterId'] as int) > 0 && (ref['from'] as int) > 0)
      .toList(growable: false);

  return <String, dynamic>{
    'post': <String, dynamic>{
      'body': body,
      'draft': false,
      if (references.isNotEmpty) 'references': references,
      'publishedAt': (publishedAt ?? DateTime.now().toUtc()).toIso8601String(),
    },
  };
}

class QuranUserSyncService {
  QuranUserSyncService._();

  static final QuranUserSyncService instance = QuranUserSyncService._();
  static const int _defaultMushafId = 4;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: <String, String>{'Accept': 'application/json'},
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  final DatabaseService _db = DatabaseService.instance;

  Future<bool> get isReadyForSync async {
    final session = await QuranUserSessionService.instance.getValidSession();
    return session?.accessToken.isNotEmpty ?? false;
  }

  Future<void> syncBookmarksToLocal() async {
    final remoteBookmarks = await fetchRemoteBookmarks();
    if (remoteBookmarks.isEmpty) {
      return;
    }

    final localBookmarks = await _db.getBookmarks();
    final localByVerseKey = <String, Bookmark>{
      for (final bookmark in localBookmarks) bookmark.verseKey: bookmark,
    };

    for (final remote in remoteBookmarks) {
      final existing = localByVerseKey[remote.verseKey];
      await _db.insertBookmark(
        Bookmark(
          id: remote.verseKey,
          verseKey: remote.verseKey,
          surahName: existing?.surahName ?? remote.surahName,
          arabicText: existing?.arabicText ?? remote.arabicText,
          translationText: existing?.translationText ?? remote.translationText,
          note: existing?.note,
          createdAt: remote.createdAt,
        ),
      );
    }
  }

  Future<void> syncLocalBookmarksToRemote() async {
    final localBookmarks = await _db.getBookmarks();
    for (final bookmark in localBookmarks) {
      final parts = bookmark.verseKey.split(':');
      if (parts.length != 2) {
        continue;
      }

      final chapterNumber = int.tryParse(parts.first);
      final verseNumber = int.tryParse(parts.last);
      if (chapterNumber == null || verseNumber == null) {
        continue;
      }

      try {
        await addVerseBookmark(
          Verse(
            verseKey: bookmark.verseKey,
            surahNumber: chapterNumber,
            ayahNumber: verseNumber,
            arabicText: bookmark.arabicText,
            translationText: bookmark.translationText,
          ),
        );
      } catch (error) {
        debugPrint(
          'UserSync: Bookmark push skipped for ${bookmark.verseKey}: $error',
        );
      }
    }
  }

  Future<List<Bookmark>> fetchRemoteBookmarks() async {
    final config = await _getConfig();
    final headers = await _authHeaders();
    if (config == null || headers == null) {
      return const <Bookmark>[];
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${config.userApiBaseUrl}/bookmarks',
        queryParameters: <String, dynamic>{
          'type': 'ayah',
          'mushafId': _defaultMushafId,
          'first': 100,
        },
        options: Options(headers: headers),
      );

      final items = (response.data?['data'] as List?) ?? const <dynamic>[];
      return items
          .map(
            (item) =>
                _bookmarkFromRemote((item as Map).cast<String, dynamic>()),
          )
          .whereType<Bookmark>()
          .toList();
    } catch (error) {
      debugPrint('UserSync: Failed to fetch remote bookmarks: $error');
      return const <Bookmark>[];
    }
  }

  Future<void> addVerseBookmark(Verse verse) async {
    final config = await _getConfig();
    final headers = await _authHeaders();
    if (config == null || headers == null) {
      return;
    }

    try {
      await _dio.post<Map<String, dynamic>>(
        '${config.userApiBaseUrl}/bookmarks',
        data: <String, dynamic>{
          'key': verse.surahNumber,
          'verseNumber': verse.ayahNumber,
          'type': 'ayah',
          'mushaf': _defaultMushafId,
        },
        options: Options(headers: headers),
      );
    } catch (error) {
      debugPrint('UserSync: Failed to add bookmark ${verse.verseKey}: $error');
    }
  }

  Future<void> removeVerseBookmark(Verse verse) async {
    final config = await _getConfig();
    final headers = await _authHeaders();
    if (config == null || headers == null) {
      return;
    }

    try {
      final lookup = await _dio.get<Map<String, dynamic>>(
        '${config.userApiBaseUrl}/bookmarks/bookmark',
        queryParameters: <String, dynamic>{
          'key': verse.surahNumber,
          'verseNumber': verse.ayahNumber,
          'type': 'ayah',
          'mushaf': _defaultMushafId,
        },
        options: Options(headers: headers),
      );

      final bookmark = lookup.data?['data'];
      final bookmarkId = bookmark is Map<String, dynamic>
          ? bookmark['id'] as String?
          : bookmark is Map
          ? bookmark['id'] as String?
          : null;

      if (bookmarkId == null || bookmarkId.isEmpty) {
        return;
      }

      await _dio.delete<Map<String, dynamic>>(
        '${config.userApiBaseUrl}/bookmarks/$bookmarkId',
        options: Options(headers: headers),
      );
    } catch (error) {
      debugPrint(
        'UserSync: Failed to remove bookmark ${verse.verseKey}: $error',
      );
    }
  }

  Future<void> updateReadingSession(Verse verse) async {
    final config = await _getConfig();
    final headers = await _authHeaders();
    if (config == null || headers == null) {
      return;
    }

    try {
      await _dio.post<Map<String, dynamic>>(
        '${config.userApiBaseUrl}/reading-sessions',
        data: <String, dynamic>{
          'chapterNumber': verse.surahNumber,
          'verseNumber': verse.ayahNumber,
        },
        options: Options(headers: headers),
      );
    } catch (error) {
      debugPrint(
        'UserSync: Failed to update reading session ${verse.verseKey}: $error',
      );
    }
  }

  Future<void> recordActivityForVerse(
    Verse verse, {
    required String date,
    int seconds = 60,
  }) async {
    final config = await _getConfig();
    final headers = await _authHeaders(includeTimezone: true);
    if (config == null || headers == null) {
      return;
    }

    try {
      await _dio.post<Map<String, dynamic>>(
        '${config.userApiBaseUrl}/activity-days',
        data: <String, dynamic>{
          'date': date,
          'type': 'QURAN',
          'seconds': seconds,
          'ranges': <String>['${verse.verseKey}-${verse.verseKey}'],
          'mushafId': _defaultMushafId,
        },
        options: Options(headers: headers),
      );
    } catch (error) {
      debugPrint(
        'UserSync: Failed to record activity for ${verse.verseKey}: $error',
      );
    }
  }

  Future<int?> fetchCurrentStreakDays() async {
    final config = await _getConfig();
    final headers = await _authHeaders(includeTimezone: true);
    if (config == null || headers == null) {
      return null;
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${config.userApiBaseUrl}/streaks/current-streak-days',
        queryParameters: const <String, dynamic>{'type': 'QURAN'},
        options: Options(headers: headers),
      );

      final data = response.data?['data'];
      if (data is List && data.isNotEmpty) {
        final days = (data.first as Map)['days'];
        if (days is num) {
          return days.toInt();
        }
      }
    } catch (error) {
      debugPrint('UserSync: Failed to fetch current streak: $error');
    }

    return null;
  }

  Future<void> syncNow() async {
    await syncLocalBookmarksToRemote();
    await syncBookmarksToLocal();
  }

  Future<QuranUserAuthConfig?> _getConfig() async {
    await QuranUserSessionService.instance.initialize();
    final ready = await isReadyForSync;
    if (!ready) {
      return null;
    }
    return QuranUserSessionService.instance.config;
  }

  Future<Map<String, String>?> _authHeaders({
    bool includeTimezone = false,
  }) async {
    final session = await QuranUserSessionService.instance.getValidSession();
    final config = QuranUserSessionService.instance.config;
    if (session == null || session.accessToken.isEmpty) {
      return null;
    }

    final headers = <String, String>{
      'x-auth-token': session.accessToken,
      'x-client-id': config.clientId,
    };

    if (includeTimezone) {
      headers['x-timezone'] = DateTime.now().timeZoneName;
    }

    return headers;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Bookmark? _bookmarkFromRemote(Map<String, dynamic> data) {
    final key = data['key'];
    final verseNumber = data['verseNumber'];
    if (key is! num || verseNumber is! num) {
      return null;
    }

    final verseKey = '${key.toInt()}:${verseNumber.toInt()}';
    final createdAtValue = data['createdAt'] as String?;
    final createdAt = createdAtValue == null
        ? DateTime.now()
        : DateTime.tryParse(createdAtValue) ?? DateTime.now();

    return Bookmark(
      id: verseKey,
      verseKey: verseKey,
      surahName: 'Surah ${key.toInt()}',
      createdAt: createdAt,
    );
  }

  // ── Posts (User API – post scopes) ───────────────────────────────────────

  String? _lastPostError;

  /// The human-readable error from the most recent post operation, if any.
  String? get lastPostError => _lastPostError;

  /// Whether the current session includes enough scope to publish reflections.
  bool get hasPublishScope {
    final session = QuranUserSessionService.instance.session;
    if (session == null) return false;
    final scopes = (session.scope ?? '').split(RegExp(r'\s+'));
    return scopes.contains('post');
  }

  /// Create and publish an LLM response as a QuranReflect post.
  Future<QFPost?> createPost({
    required String body,
    List<String> verseKeys = const [],
  }) async {
    _lastPostError = null;
    final config = await _getConfig();
    final headers = await _authHeaders();
    if (config == null || headers == null) {
      _lastPostError = 'Not signed in.';
      return null;
    }

    final tokenScope = QuranUserSessionService.instance.session?.scope ?? '';
    if (!hasPublishScope) {
      _lastPostError =
          'Your current session is missing the approved QuranReflect post scope. Sign out and sign in again to refresh your token.';
      debugPrint(
        'UserSync: createPost blocked before request because token is missing post scope. tokenScope=$tokenScope',
      );
      return null;
    }

    final trimmed = body.trim();
    if (trimmed.length < 6) {
      _lastPostError = 'Post must be at least 6 characters.';
      return null;
    }

    final requestHeaders = <String, String>{
      ...headers,
      'Content-Type': 'application/json',
    };
    final requestOptions = Options(
      headers: requestHeaders,
      validateStatus: (status) => status != null && status < 600,
    );

    final cappedBody = trimmed.length > 10000
        ? trimmed.substring(0, 10000)
        : trimmed;

    try {
      final publishPayload = _postPayload(
        body: cappedBody,
        verseKeys: verseKeys,
      );
      debugPrint(
        'UserSync: createPost → POST ${config.quranReflectApiBaseUrl}/posts  '
        'tokenScope=$tokenScope  clientId=${config.clientId}  '
        'bodyLen=${cappedBody.length}  verseKeys=$verseKeys',
      );

      final response = await _dio.post<Map<String, dynamic>>(
        '${config.quranReflectApiBaseUrl}/posts',
        data: publishPayload,
        options: requestOptions,
      );

      debugPrint(
        'UserSync: createPost response status=${response.statusCode} '
        'body=${response.data}',
      );

      if ((response.statusCode ?? 0) >= 400) {
        final message = _responseMessage(response.data);
        _lastPostError = message == null
            ? 'Could not publish reflection (${response.statusCode}).'
            : 'Could not publish reflection (${response.statusCode}): $message';
        return null;
      }

      _lastPostError = null;
      return _extractPost(response.data?['post'], trimmed);
    } catch (error) {
      _lastPostError = 'Network error – check your connection.';
      debugPrint('UserSync: Failed to create post: $error');
      return null;
    }
  }

  Map<String, dynamic> _postPayload({
    required String body,
    required List<String> verseKeys,
  }) {
    return buildQuranReflectPostPayload(body: body, verseKeys: verseKeys);
  }

  String? _responseMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final message = data['message'] as String?;
      final errorDescription = data['error_description'] as String?;
      return message ?? errorDescription;
    }
    return null;
  }

  QFPost _extractPost(dynamic data, String fallbackBody) {
    if (data is Map<String, dynamic>) {
      return _postFromRemote(data) ??
          QFPost(id: '', body: fallbackBody, createdAt: DateTime.now());
    }
    if (data is List && data.isNotEmpty) {
      return _postFromRemote((data.first as Map).cast<String, dynamic>()) ??
          QFPost(id: '', body: fallbackBody, createdAt: DateTime.now());
    }
    return QFPost(id: '', body: fallbackBody, createdAt: DateTime.now());
  }

  /// Fetch the signed-in user's reflections (newest first).
  Future<List<QFPost>> listPosts({int limit = 20}) async {
    final config = await _getConfig();
    final headers = await _authHeaders();
    if (config == null || headers == null) {
      return const <QFPost>[];
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${config.quranReflectApiBaseUrl}/posts/my-posts',
        queryParameters: <String, dynamic>{
          'tab': 'my_reflections',
          'sortBy': 'latest',
          'limit': limit > 20 ? 20 : limit,
          'page': 1,
        },
        options: Options(headers: headers),
      );

      final items = (response.data?['data'] as List?) ?? const <dynamic>[];
      return items
          .map((item) => _postFromRemote((item as Map).cast<String, dynamic>()))
          .whereType<QFPost>()
          .toList(growable: false);
    } catch (error) {
      debugPrint('UserSync: Failed to fetch posts: $error');
      return const <QFPost>[];
    }
  }

  /// Delete a published reflection by its ID.
  Future<bool> deletePost(String noteId) async {
    final config = await _getConfig();
    final headers = await _authHeaders();
    if (config == null || headers == null) return false;

    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        '${config.quranReflectApiBaseUrl}/posts/$noteId',
        options: Options(headers: headers),
      );
      return (response.statusCode ?? 0) < 400;
    } catch (error) {
      debugPrint('UserSync: Failed to delete post $noteId: $error');
      return false;
    }
  }

  QFPost? _postFromRemote(Map<String, dynamic> data) {
    final id = (data['id'] ?? '').toString();
    final body = (data['body'] ?? '').toString();
    final authorMap = data['author'] as Map<String, dynamic>?;
    final author =
        (authorMap?['displayName'] ??
                authorMap?['username'] ??
                authorMap?['firstName'])
            ?.toString();
    final references = data['references'] as List?;
    final verseRanges = <String>[];
    if (references != null) {
      for (final ref in references.whereType<Map>()) {
        final chapterId = ref['chapterId'];
        final from = ref['from'];
        final to = ref['to'];
        if (chapterId is num && from is num && to is num) {
          verseRanges.add(
            '${chapterId.toInt()}:${from.toInt()}-${chapterId.toInt()}:${to.toInt()}',
          );
        }
      }
    }
    final createdAtValue = data['createdAt'] as String?;
    final createdAt = createdAtValue == null
        ? DateTime.now()
        : DateTime.tryParse(createdAtValue) ?? DateTime.now();
    return QFPost(
      id: id,
      body: body,
      createdAt: createdAt,
      author: author,
      verseRanges: verseRanges,
    );
  }

  // ── Community reflections feed (Content API – post.read via backend) ─────

  /// Fetch the public QuranReflect post feed through the backend proxy.
  Future<List<QFPost>> fetchCommunityFeed({int limit = 20}) async {
    await QuranApiConfigService.instance.initialize();
    final baseUrl = QuranApiConfigService
        .instance
        .config
        .quranFoundationBackendBaseUrl
        .trim();
    if (baseUrl.isEmpty) return const <QFPost>[];

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/qf/posts/feed',
        queryParameters: <String, dynamic>{'limit': limit},
      );

      final posts = response.data?['posts'] as List?;
      if (posts == null) return const <QFPost>[];

      return posts
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final id = (item['id'] ?? '').toString();
            final body = (item['body'] ?? '').toString();
            final author = (item['authorName'] ?? '').toString();
            final createdAtStr = item['createdAt'] as String?;
            final createdAt = createdAtStr == null
                ? DateTime.now()
                : DateTime.tryParse(createdAtStr) ?? DateTime.now();
            final ranges = <String>[];
            final rawRanges = item['ranges'];
            if (rawRanges is List) {
              for (final r in rawRanges) {
                ranges.add(r.toString());
              }
            }
            return QFPost(
              id: id,
              body: body,
              createdAt: createdAt,
              author: author.isNotEmpty ? author : null,
              verseRanges: ranges,
            );
          })
          .toList(growable: false);
    } catch (error) {
      debugPrint('UserSync: Failed to fetch community feed: $error');
      return const <QFPost>[];
    }
  }
}

/// A published note/post on QuranReflect.
class QFPost {
  const QFPost({
    required this.id,
    required this.body,
    required this.createdAt,
    this.author,
    this.verseRanges = const [],
  });

  final String id;
  final String body;
  final DateTime createdAt;
  final String? author;
  final List<String> verseRanges;
}
