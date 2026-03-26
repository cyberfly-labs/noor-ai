import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/bookmark.dart';
import '../models/verse.dart';
import 'database_service.dart';
import 'quran_user_session_service.dart';

class QuranUserSyncService {
  QuranUserSyncService._();

  static final QuranUserSyncService instance = QuranUserSyncService._();
  static const int _defaultMushafId = 4;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: <String, String>{'Accept': 'application/json'},
    validateStatus: (status) => status != null && status < 500,
  ));

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
        debugPrint('UserSync: Bookmark push skipped for ${bookmark.verseKey}: $error');
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
          .map((item) => _bookmarkFromRemote((item as Map).cast<String, dynamic>()))
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
      debugPrint('UserSync: Failed to remove bookmark ${verse.verseKey}: $error');
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
      debugPrint('UserSync: Failed to update reading session ${verse.verseKey}: $error');
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
      debugPrint('UserSync: Failed to record activity for ${verse.verseKey}: $error');
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

  Future<Map<String, String>?> _authHeaders({bool includeTimezone = false}) async {
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

  // ── Posts (Notes with saveToQR=true → publishes to QuranReflect) ────────

  /// Create and publish an LLM response as a post on QuranReflect.
  ///
  /// [body] is the text content (6–10000 chars).
  /// [verseKeys] are Quran citation keys in "surah:ayah" format (e.g. "2:255").
  /// Returns the created [QFPost] or null on failure.
  Future<QFPost?> createPost({
    required String body,
    List<String> verseKeys = const [],
  }) async {
    final config = await _getConfig();
    final headers = await _authHeaders();
    if (config == null || headers == null) {
      return null;
    }

    final trimmed = body.trim();
    if (trimmed.length < 6) {
      return null;
    }

    // API expects ranges in "surah:ayah-surah:ayah" format.
    final ranges = verseKeys
        .map((k) => k.trim())
        .where((k) => k.contains(':'))
        .map((k) => '$k-$k')
        .toList(growable: false);

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${config.userApiBaseUrl}/notes',
        data: <String, dynamic>{
          'body': trimmed.length > 10000 ? trimmed.substring(0, 10000) : trimmed,
          'saveToQR': true,
          if (ranges.isNotEmpty) 'ranges': ranges,
        },
        options: Options(
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json',
          },
        ),
      );

      if ((response.statusCode ?? 0) >= 400) {
        debugPrint('UserSync: createPost failed status=${response.statusCode}');
        return null;
      }

      final data = response.data?['data'];
      if (data is Map<String, dynamic>) {
        return _postFromRemote(data);
      }
      // Some environments wrap in a list
      if (data is List && data.isNotEmpty) {
        return _postFromRemote((data.first as Map).cast<String, dynamic>());
      }
      // Success but no body — treat as ok with stub
      return QFPost(id: '', body: trimmed, createdAt: DateTime.now());
    } catch (error) {
      debugPrint('UserSync: Failed to create post: $error');
      return null;
    }
  }

  /// Fetch the signed-in user's published notes/posts (newest first).
  Future<List<QFPost>> listPosts({int limit = 20}) async {
    final config = await _getConfig();
    final headers = await _authHeaders();
    if (config == null || headers == null) {
      return const <QFPost>[];
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${config.userApiBaseUrl}/notes',
        queryParameters: <String, dynamic>{
          'limit': limit,
          'sortBy': 'newest',
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

  /// Delete a published note/post by its ID.
  Future<bool> deletePost(String noteId) async {
    final config = await _getConfig();
    final headers = await _authHeaders();
    if (config == null || headers == null) {
      return false;
    }

    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        '${config.userApiBaseUrl}/notes/$noteId',
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
    final createdAtValue = data['createdAt'] as String?;
    final createdAt = createdAtValue == null
        ? DateTime.now()
        : DateTime.tryParse(createdAtValue) ?? DateTime.now();
    return QFPost(id: id, body: body, createdAt: createdAt);
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
}

/// A published note/post on QuranReflect.
class QFPost {
  const QFPost({
    required this.id,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String body;
  final DateTime createdAt;
}