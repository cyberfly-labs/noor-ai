import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/chapter_info.dart';
import '../models/juz_info.dart';
import '../models/quran_recitation_resource.dart';
import '../models/quran_tafsir_resource.dart';
import '../models/quran_translation_resource.dart';
import '../models/reflection_post.dart';
import '../models/verse.dart';
import '../models/surah.dart';
import 'quran_api_config_service.dart';
import 'quran_mcp_service.dart';
import 'database_service.dart';

/// Quran content client with backend-compatible Quran Foundation support.
class QuranApiService {
  QuranApiService._();
  static final QuranApiService instance = QuranApiService._();

  static const _alQuranCloudBaseUrl = 'https://api.alquran.cloud/v1';
  static const _quranFoundationAudioBaseUrl =
      'https://verses.quran.foundation/';
  static const _defaultQuranFoundationTafsirId = 169;
  static const List<int> _ayahCountsBySurah = <int>[
    7,
    286,
    200,
    176,
    120,
    165,
    206,
    75,
    129,
    109,
    123,
    111,
    43,
    52,
    99,
    128,
    111,
    110,
    98,
    135,
    112,
    78,
    118,
    64,
    77,
    227,
    93,
    88,
    69,
    60,
    34,
    30,
    73,
    54,
    45,
    83,
    182,
    88,
    75,
    85,
    54,
    53,
    89,
    59,
    37,
    35,
    38,
    29,
    18,
    45,
    60,
    49,
    62,
    55,
    78,
    96,
    29,
    22,
    24,
    13,
    14,
    11,
    11,
    18,
    12,
    12,
    30,
    52,
    52,
    44,
    28,
    28,
    20,
    56,
    40,
    31,
    50,
    40,
    46,
    42,
    29,
    19,
    36,
    25,
    22,
    17,
    19,
    26,
    30,
    20,
    15,
    21,
    11,
    8,
    8,
    19,
    5,
    8,
    8,
    11,
    11,
    8,
    3,
    9,
    5,
    4,
    7,
    3,
    6,
    3,
    5,
    4,
    5,
    6,
  ];

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  String? _tafsirResourceCacheKey;
  Future<List<QuranTafsirResource>>? _tafsirResourcesFuture;

  Future<QuranApiConfig> _getConfig() async {
    final service = QuranApiConfigService.instance;
    await service.initialize();
    return service.config;
  }

  void _invalidateTafsirCacheIfNeeded(QuranApiConfig config) {
    final cacheKey = [
      config.quranFoundationBaseUrl,
      config.usePrelive,
    ].join('|');

    if (_tafsirResourceCacheKey == cacheKey) {
      return;
    }

    _tafsirResourceCacheKey = cacheKey;
    _tafsirResourcesFuture = null;
  }

  Map<String, String> _quranFoundationHeaders(QuranApiConfig config) {
    if (config.usesQuranFoundationBackend) {
      return const <String, String>{};
    }

    return <String, String>{
      'x-auth-token': config.quranFoundationAuthToken,
      'x-client-id': config.quranFoundationClientId,
    };
  }

  String _normalizeQuranFoundationAudioUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return '';
    }
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final normalizedPath = trimmed.startsWith('/')
        ? trimmed.substring(1)
        : trimmed;
    return '$_quranFoundationAudioBaseUrl$normalizedPath';
  }

  Map<String, dynamic>? _mapFromData(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    return null;
  }

  List<dynamic> _listFromData(dynamic data) {
    if (data is List) {
      return data;
    }
    return const [];
  }

  Future<List<QuranTafsirResource>> listTafsirResources() async {
    final config = await _getConfig();
    if (!config.usesQuranFoundation) {
      return const [];
    }

    _invalidateTafsirCacheIfNeeded(config);
    final pending = _tafsirResourcesFuture;
    if (pending != null) {
      return pending;
    }

    final future = _loadTafsirResources(config);
    _tafsirResourcesFuture = future;

    try {
      return await future;
    } catch (_) {
      if (identical(_tafsirResourcesFuture, future)) {
        _tafsirResourcesFuture = null;
      }
      rethrow;
    }
  }

  Future<List<QuranTafsirResource>> _loadTafsirResources(
    QuranApiConfig config,
  ) async {
    try {
      final response = await _quranFoundationGet(
        '/resources/tafsirs',
        config: config,
        queryParameters: const <String, dynamic>{'language': 'en'},
      );
      final data = _mapFromData(response.data);
      final tafsirs = _listFromData(data?['tafsirs']);

      return tafsirs
          .map(
            (item) => QuranTafsirResource.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .where((item) => item.id > 0)
          .toList(growable: false);
    } catch (e) {
      debugPrint('QuranAPI: Failed to list tafsir resources: $e');
      return const [];
    }
  }

  Future<Response<dynamic>> _alQuranCloudGet(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.get(
      '$_alQuranCloudBaseUrl$path',
      queryParameters: queryParameters,
    );
  }

  Future<Response<dynamic>> _quranFoundationGet(
    String path, {
    required QuranApiConfig config,
    Map<String, dynamic>? queryParameters,
  }) {
    final headers = _quranFoundationHeaders(config);
    return _dio.get(
      '${config.quranFoundationBaseUrl}$path',
      queryParameters: queryParameters,
      options: headers.isEmpty ? null : Options(headers: headers),
    );
  }

  // ── Tafsir ──

  Future<String?> getVerseTafsir(
    int surahNumber,
    int ayahNumber, {
    int tafsirId = 169, // Default to Ibn Kathir (English)
  }) async {
    final verseKey = '$surahNumber:$ayahNumber';
    try {
      final response = await _dio.get(
        'https://api.quran.com/api/v4/tafsirs/$tafsirId/by_ayah/$verseKey',
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final tafsir = data['tafsir'];
        if (tafsir != null) {
          return _stripHtml(tafsir['text'] as String? ?? '');
        }
      }
    } catch (e) {
      debugPrint('QuranAPI: Failed to fetch tafsir for $verseKey: $e');
    }
    return null;
  }

  Future<String?> getVerseTafsirSource(
    int surahNumber,
    int ayahNumber, {
    int tafsirId = 169,
  }) async {
    return 'Quran.com';
  }

  int? _maxAyahsForSurah(int surahNumber) {
    if (surahNumber < 1 || surahNumber > _ayahCountsBySurah.length) {
      return null;
    }
    return _ayahCountsBySurah[surahNumber - 1];
  }

  int? getAyahCountForSurah(int surahNumber) {
    return _maxAyahsForSurah(surahNumber);
  }

  bool _isValidVerseReference(int surahNumber, int ayahNumber) {
    final maxAyahs = _maxAyahsForSurah(surahNumber);
    return maxAyahs != null && ayahNumber >= 1 && ayahNumber <= maxAyahs;
  }

  // ── Verse Retrieval ──

  Future<ChapterInfo?> getChapterInfo(int surahNumber) async {
    try {
      final response = await _dio.get(
        'https://api.quran.com/api/v4/chapters/$surahNumber/info',
        queryParameters: {'language': 'en'},
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final info = data['chapter_info'];
        if (info != null) {
          return ChapterInfo.fromJson(info);
        }
      }
    } catch (e) {
      debugPrint('QuranAPI: Failed to fetch chapter info for $surahNumber: $e');
    }
    return null;
  }

  Future<Verse?> getVerse(int surahNumber, int ayahNumber) async {
    final verseKey = '$surahNumber:$ayahNumber';

    // Check local cache first
    try {
      final cached = await DatabaseService.instance.getCachedVerse(verseKey);
      if (cached != null) {
        return Verse(
          verseKey: verseKey,
          surahNumber: surahNumber,
          ayahNumber: ayahNumber,
          arabicText: cached['arabic_text'] ?? '',
          translationText: cached['translation_text'] ?? '',
          audioUrl: cached['audio_url'] ?? '',
          transliteration: '',
        );
      }
    } catch (e) {
      debugPrint('Error reading verse cache: $e');
    }

    // Fetch from Quran.com API
    try {
      final response = await _dio.get(
        'https://api.quran.com/api/v4/verses/by_key/$verseKey',
        queryParameters: {
          'language': 'en',
          'words': 'false',
          'translations': '131', // Clear Quran (Dr. Mustafa Khattab)
          'fields': 'text_uthmani',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final verseData = data['verse'] as Map<String, dynamic>?;
        
        if (verseData != null) {
          final arabicText = (verseData['text_uthmani'] as String? ?? '').trim();
          final translations = verseData['translations'] as List?;
          String translationText = '';
          if (translations != null && translations.isNotEmpty) {
            translationText = _stripHtml(translations.first['text'] as String? ?? '');
          }

          final verse = Verse(
            verseKey: verseKey,
            surahNumber: surahNumber,
            ayahNumber: ayahNumber,
            arabicText: arabicText,
            translationText: translationText,
            transliteration: '',
          );

          // Save to cache
          try {
            await DatabaseService.instance.cacheVerse({
              'verse_key': verseKey,
              'surah_number': surahNumber,
              'ayah_number': ayahNumber,
              'arabic_text': arabicText,
              'translation_text': translationText,
              'audio_url': verse.audioUrl,
            });
          } catch (e) {
            debugPrint('Error saving verse cache: $e');
          }

          return verse;
        }
      }
    } catch (e) {
      debugPrint('QuranAPI: Failed to fetch verse $verseKey: $e');
    }

    return null;
  }

  String _stripHtml(String html) {
    if (html.isEmpty) return '';
    
    // Replace structural HTML tags with newlines before stripping
    String processed = html
        .replaceAll(RegExp(r'</p>|<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<li>'), '\n• ')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lsquo;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&ldquo;', '"')
        .replaceAll('&rdquo;', '"')
        .replaceAll('&#39;', "'");

    // Normalize multiple newlines and trim
    return processed
        .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
        .trim();
  }

  Future<List<Verse>> getSurahVerses(int surahNumber) async {
    final maxAyahs = _maxAyahsForSurah(surahNumber) ?? 0;
    final verses = <Verse>[];
    
    for (int i = 1; i <= maxAyahs; i++) {
      final v = await getVerse(surahNumber, i);
      if (v != null) verses.add(v);
      if (i > 15) break; 
    }
    return verses;
  }

  // ── Surah List ──

  Future<List<Surah>> listSurahs() async {
    // 1. Try local cache first
    try {
      final cachedChapters = await DatabaseService.instance.getCachedSurahs();
      if (cachedChapters.isNotEmpty && cachedChapters.length == 114) {
        debugPrint('QuranAPI: Returning surahs from local cache');
        return cachedChapters.map((c) {
          final number = c['id'] as int? ?? c['chapter_number'] as int? ?? c['number'] as int? ?? 0;
          return Surah(
            number: number,
            name: c['name_arabic'] ?? '',
            englishName: c['name_simple'] ?? c['name_complex'] ?? '',
            englishNameTranslation: c['translated_name']?['name'] ?? '',
            numberOfAyahs: c['verses_count'] as int? ?? 0,
            revelationType: c['revelation_place'] ?? 'meccan',
            pages: (c['pages'] as List?)?.cast<int>() ?? [],
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('QuranAPI: Cache read error: $e');
    }

    // 2. Fetch from Quran.com API
    try {
      debugPrint('QuranAPI: Fetching surahs from api.quran.com...');
      final response = await _dio.get(
        'https://api.quran.com/api/v4/chapters',
        queryParameters: {'language': 'en'},
      );
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final chapters = data['chapters'] as List;
        
        // Save to cache
        try {
          await DatabaseService.instance.insertSurahs(
            chapters.map((c) => Map<String, dynamic>.from(c as Map)).toList()
          );
        } catch (e) {
          debugPrint('QuranAPI: Cache save error: $e');
        }

        return chapters.map((c) {
          final map = c as Map<String, dynamic>;
          return Surah(
            number: map['id'] as int,
            name: map['name_arabic'] ?? '',
            englishName: map['name_simple'] ?? map['name_complex'] ?? '',
            englishNameTranslation: map['translated_name']?['name'] ?? '',
            numberOfAyahs: map['verses_count'] as int? ?? 0,
            revelationType: map['revelation_place'] ?? 'meccan',
            pages: (map['pages'] as List?)?.cast<int>() ?? [],
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('QuranAPI: Remote fetch error: $e');
    }

    // 3. Fallback: Return empty if remote fetch fails
    return [];
  }

  Future<List<QuranTranslationResource>> listTranslationResources() async {
    final config = await _getConfig();
    if (!config.usesQuranFoundation) {
      return const [];
    }

    try {
      final response = await _quranFoundationGet(
        '/resources/translations',
        config: config,
        queryParameters: const <String, dynamic>{'language': 'en'},
      );
      final data = _mapFromData(response.data);
      final translations = _listFromData(data?['translations']);

      return translations
          .map(
            (item) => QuranTranslationResource.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .where((item) => item.id > 0)
          .toList(growable: false);
    } catch (e) {
      debugPrint('QuranAPI: Failed to list translation resources: $e');
      return const [];
    }
  }

  Future<List<QuranRecitationResource>> listRecitationResources() async {
    final config = await _getConfig();
    if (!config.usesQuranFoundation) {
      return const [];
    }

    try {
      final response = await _quranFoundationGet(
        '/resources/recitations',
        config: config,
        queryParameters: const <String, dynamic>{'language': 'en'},
      );
      final data = _mapFromData(response.data);
      final recitations = _listFromData(data?['recitations']);

      return recitations
          .map(
            (item) => QuranRecitationResource.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .where((item) => item.id > 0)
          .toList(growable: false);
    } catch (e) {
      debugPrint('QuranAPI: Failed to list recitation resources: $e');
      return const [];
    }
  }

  // ── Juzs ──

  /// Fetches the list of all 30 Juzs with their verse mappings.
  Future<List<JuzInfo>> listJuzs() async {
    final config = await _getConfig();
    if (!config.usesQuranFoundation) {
      return const [];
    }

    try {
      final response = await _quranFoundationGet('/juzs', config: config);
      final data = _mapFromData(response.data);
      final juzs = _listFromData(data?['juzs']);
      return juzs
          .map((item) => JuzInfo.fromJson((item as Map).cast<String, dynamic>()))
          .where((j) => j.juzNumber > 0)
          .toList(growable: false);
    } catch (e) {
      debugPrint('QuranAPI: Failed to list juzs: $e');
      return const [];
    }
  }

  // ── Reflections Feed (Quran Reflect) ──

  /// Fetches the Quran Reflect community feed (lessons & reflections).
  /// [page] is 1-based.
  Future<List<ReflectionPost>> fetchReflectionsFeed({
    int page = 1,
    int perPage = 20,
    String language = 'en',
  }) async {
    final config = await _getConfig();
    if (!config.usesQuranFoundation) {
      return const [];
    }

    try {
      final response = await _quranFoundationGet(
        '/posts/feed',
        config: config,
        queryParameters: <String, dynamic>{
          'page': page,
          'per_page': perPage,
          'language': language,
        },
      );
      final data = _mapFromData(response.data);
      final posts = _listFromData(data?['posts'] ?? data?['data']);
      return posts
          .whereType<Map>()
          .map((item) => ReflectionPost.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (e) {
      debugPrint('QuranAPI: Failed to fetch reflections feed: $e');
      return const [];
    }
  }

  // ── Search ──

  Future<List<Verse>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return [];
    }

    final results = await QuranMcpService.instance.searchQuran(trimmed);
    return results.map((r) {
      final verseKey = r['ayah_key'] as String? ?? r['verse_key'] as String? ?? '';
      final parts = verseKey.split(':');
      final sn = parts.length == 2 ? int.tryParse(parts[0]) : null;
      final an = parts.length == 2 ? int.tryParse(parts[1]) : null;
      
      return Verse(
        verseKey: verseKey,
        surahNumber: sn ?? 0,
        ayahNumber: an ?? 0,
        translationText: (r['translations'] as List?)?.first['text'] ?? r['text'] ?? '',
      );
    }).toList();
  }

  // ── Audio ──

  Future<String?> getAudioUrl(int surahNumber, int ayahNumber) async {
    if (!_isValidVerseReference(surahNumber, ayahNumber)) {
      debugPrint(
        'QuranAPI: Invalid audio verse reference $surahNumber:$ayahNumber',
      );
      return null;
    }

    final config = await _getConfig();
    final verseKey = '$surahNumber:$ayahNumber';

    if (config.usesQuranFoundation) {
      try {
        final response = await _quranFoundationGet(
          '/recitations/${config.recitationId}/by_ayah/$verseKey',
          config: config,
        );

        if (response.statusCode == 404) {
          return null;
        }

        final data = _mapFromData(response.data);
        final audioFiles = _listFromData(data?['audio_files']);

        for (final item in audioFiles) {
          final audioFile = _mapFromData(item);
          if (audioFile == null) {
            continue;
          }
          if (audioFile['verse_key'] == verseKey) {
            final normalized = _normalizeQuranFoundationAudioUrl(
              audioFile['url'] as String?,
            );
            return normalized.isEmpty ? null : normalized;
          }
        }

        if (audioFiles.isNotEmpty) {
          final fallbackAudio = _mapFromData(audioFiles.first);
          final normalized = _normalizeQuranFoundationAudioUrl(
            fallbackAudio?['url'] as String?,
          );
          return normalized.isEmpty ? null : normalized;
        }
      } catch (e) {
        debugPrint(
          'QuranAPI: Quran Foundation audio fetch failed for $verseKey, falling back: $e',
        );
      }
    }

    try {
      final response = await _alQuranCloudGet(
        '/ayah/$surahNumber:$ayahNumber/ar.alafasy',
      );

      if (response.statusCode == 404) return null;
      final data = _mapFromData(response.data);
      if (data?['code'] != 200) return null;
      return data?['data']?['audio'] as String?;
    } catch (e) {
      debugPrint('QuranAPI: Failed to get audio: $e');
      return null;
    }
  }

  Future<List<String>> getSurahAudioUrls(
    int surahNumber, {
    List<Verse>? verses,
  }) async {
    final sourceVerses = verses ?? await getSurahVerses(surahNumber);
    final urls = <String>[];

    for (final verse in sourceVerses) {
      final inlineUrl = _normalizeQuranFoundationAudioUrl(verse.audioUrl);
      if (inlineUrl.isNotEmpty) {
        urls.add(inlineUrl);
        continue;
      }

      final fetchedUrl = await getAudioUrl(verse.surahNumber, verse.ayahNumber);
      if (fetchedUrl != null && fetchedUrl.trim().isNotEmpty) {
        urls.add(fetchedUrl.trim());
      }
    }

    return urls;
  }

  // ── Random Verse (for Daily Ayah) ──

  Future<Verse?> getRandomVerse() async {
    // Try the public Quran Foundation API for a truly random verse
    try {
      final response = await _dio.get(
        'https://api.quran.com/api/v4/verses/random',
        queryParameters: {
          'language': 'en',
          'fields': 'text_uthmani,verse_key,chapter_id',
          'translations': '131',
        },
      );
      final data = _mapFromData(response.data);
      final verse = _mapFromData(data?['verse']);
      if (verse != null) {
        final verseKey = verse['verse_key'] as String?;
        final arabicText = (verse['text_uthmani'] as String? ?? '').trim();
        if (verseKey != null && verseKey.isNotEmpty) {
          final parts = verseKey.split(':');
          final surahNumber = int.tryParse(parts[0]) ?? 1;
          final ayahNumber = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;

          final translations = verse['translations'] as List?;
          String translationText = '';
          if (translations != null && translations.isNotEmpty) {
            translationText = _stripHtml(translations.first['text'] as String? ?? '');
          }

          return Verse(
            verseKey: verseKey,
            surahNumber: surahNumber,
            ayahNumber: ayahNumber,
            arabicText: arabicText,
            translationText: translationText,
          );
        }
      }
    } catch (e) {
      debugPrint('QuranAPI: Random verse fetch failed, using deterministic fallback: $e');
    }

    // Deterministic fallback based on day of year
    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year, 1, 1))
        .inDays;
    final surah = (dayOfYear * 7 + 13) % 114 + 1;
    final maxAyahs = _maxAyahsForSurah(surah) ?? 1;
    final ayah = (dayOfYear * 3 + 5) % maxAyahs + 1;

    return getVerse(surah, ayah);
  }
}
