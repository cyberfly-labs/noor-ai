import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/chapter_info.dart';
import '../models/quran_recitation_resource.dart';
import '../models/quran_tafsir_resource.dart';
import '../models/quran_translation_resource.dart';
import '../models/verse.dart';
import '../models/surah.dart';
import 'quran_api_config_service.dart';

/// Quran content client with backend-compatible Quran Foundation support.
class QuranApiService {
  QuranApiService._();
  static final QuranApiService instance = QuranApiService._();

  static const _alQuranCloudBaseUrl = 'https://api.alquran.cloud/v1';
  static const _quranFoundationAudioBaseUrl = 'https://verses.quran.foundation/';
  static const _defaultQuranFoundationTafsirId = 169;
  static const List<int> _ayahCountsBySurah = <int>[
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111,
    43, 52, 99, 128, 111, 110, 98, 135, 112, 78, 118, 64,
    77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83,
    182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29,
    18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
    14, 11, 11, 18, 12, 12, 30, 52, 52, 44, 28, 28,
    20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25,
    22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19,
    5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3,
    6, 3, 5, 4, 5, 6,
  ];

  late final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Accept': 'application/json'},
    validateStatus: (status) => status != null && status < 500,
  ));
  String? _tafsirResourceCacheKey;
  Future<List<QuranTafsirResource>>? _tafsirResourcesFuture;
  int? _preferredEnglishTafsirId;

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
    _preferredEnglishTafsirId = null;
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
    final normalizedPath = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    return '$_quranFoundationAudioBaseUrl$normalizedPath';
  }

  Verse _verseFromQuranFoundation(Map<String, dynamic> json) {
    final verse = json['verse'] as Map<String, dynamic>? ?? json;
    final translations = (json['translations'] as List?) ??
        (verse['translations'] as List?) ??
        const [];
    final audio = json['audio'] as Map<String, dynamic>? ??
        verse['audio'] as Map<String, dynamic>?;

    return Verse(
      verseKey: verse['verse_key'] as String? ??
          '${verse['chapter_id']}:${verse['verse_number']}',
      surahNumber: verse['chapter_id'] as int? ?? 0,
      ayahNumber: verse['verse_number'] as int? ?? 0,
      arabicText: verse['text_uthmani'] as String? ?? verse['text'] as String?,
      translationText: translations.isNotEmpty
          ? (translations.first as Map<String, dynamic>)['text'] as String?
          : null,
      transliteration: verse['transliteration']?['text'] as String?,
      audioUrl: _normalizeQuranFoundationAudioUrl(audio?['url'] as String?),
    );
  }

  ChapterInfo _chapterInfoFromQuranFoundation(Map<String, dynamic> json) {
    final info = _mapFromData(json['chapter_info']) ?? json;

    return ChapterInfo.fromJson(<String, dynamic>{
      'id': info['id'] as int? ?? 0,
      'chapter_id': info['chapter_id'] as int? ?? 0,
      'language_name': info['language_name'] as String? ?? '',
      'short_text': _cleanText(info['short_text']) ?? '',
      'source': _cleanText(info['source']) ?? '',
      'text': _cleanText(info['text']) ?? '',
    });
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

  String _stripHtml(String input) {
    final withoutBreaks = input
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');

    return withoutBreaks
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  String? _cleanText(dynamic value) {
    if (value is! String) {
      return null;
    }
    final cleaned = _stripHtml(value);
    return cleaned.isEmpty ? null : cleaned;
  }

  int? _parseAyahNumber(dynamic value) {
    if (value is int) {
      return value > 0 ? value : null;
    }

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }

      final direct = int.tryParse(trimmed);
      if (direct != null && direct > 0) {
        return direct;
      }

      final verseMatch = RegExp(r':(\d+)$').firstMatch(trimmed);
      if (verseMatch != null) {
        return int.tryParse(verseMatch.group(1)!);
      }
    }

    return null;
  }

  bool _matchesAyahRangeKey(String value, int ayahNumber) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final parts = trimmed.split('-');
    final start = _parseAyahNumber(parts.first);
    if (start == null) {
      return false;
    }

    var endSource = parts.first;
    if (parts.length > 1) {
      final rawEnd = parts.last.trim();
      final surahPrefix = parts.first.contains(':')
          ? parts.first.split(':').first.trim()
          : '';
      endSource = rawEnd.contains(':') || surahPrefix.isEmpty
          ? rawEnd
          : '$surahPrefix:$rawEnd';
    }

    final end = _parseAyahNumber(endSource) ?? start;
    return ayahNumber >= start && ayahNumber <= end;
  }

  bool _tafsirItemMatchesAyah(Map<String, dynamic> item, int ayahNumber) {
    for (final field in <String>['ayah_number', 'verse_number']) {
      final direct = _parseAyahNumber(item[field]);
      if (direct != null) {
        return direct == ayahNumber;
      }
    }

    final rangeKey = item['group_verse_key'] as String?;
    if (rangeKey != null && _matchesAyahRangeKey(rangeKey, ayahNumber)) {
      return true;
    }

    final verseKey = item['verse_key'] as String?;
    if (verseKey != null && _matchesAyahRangeKey(verseKey, ayahNumber)) {
      return true;
    }

    final startVerseNumber = _parseAyahNumber(item['start_verse_number']);
    final endVerseNumber = _parseAyahNumber(item['end_verse_number']);
    if (startVerseNumber != null) {
      final end = endVerseNumber ?? startVerseNumber;
      if (ayahNumber >= startVerseNumber && ayahNumber <= end) {
        return true;
      }
    }

    final startVerseKey = item['start_verse_key'] as String?;
    final endVerseKey = item['end_verse_key'] as String?;
    if (startVerseKey != null) {
      final rangeValue = endVerseKey == null || endVerseKey.trim().isEmpty
          ? startVerseKey
          : '$startVerseKey-$endVerseKey';
      if (_matchesAyahRangeKey(rangeValue, ayahNumber)) {
        return true;
      }
    }

    return false;
  }

  Map<String, dynamic>? _selectTafsirItemFromQuranFoundation(
    dynamic data, {
    int? ayahNumber,
  }) {
    final map = _mapFromData(data);
    final tafsir = _mapFromData(map?['tafsir']);
    if (tafsir != null && (ayahNumber == null || _tafsirItemMatchesAyah(tafsir, ayahNumber))) {
      return tafsir;
    }

    Map<String, dynamic>? fallback;
    final tafsirs = _listFromData(map?['tafsirs']);
    for (final item in tafsirs) {
      final tafsirItem = _mapFromData(item);
      if (tafsirItem == null) {
        continue;
      }
      fallback ??= tafsirItem;
      if (ayahNumber == null || _tafsirItemMatchesAyah(tafsirItem, ayahNumber)) {
        return tafsirItem;
      }
    }

    return fallback;
  }

  String? _cleanTafsirTextFromQuranFoundation(
    dynamic data, {
    int? ayahNumber,
  }) {
    final item = _selectTafsirItemFromQuranFoundation(
      data,
      ayahNumber: ayahNumber,
    );
    return _cleanText(item?['text']);
  }

  String? _tafsirSourceNameFromQuranFoundation(
    dynamic data, {
    int? ayahNumber,
  }) {
    final item = _selectTafsirItemFromQuranFoundation(
      data,
      ayahNumber: ayahNumber,
    );
    final directName = item?['resource_name'] as String? ??
        item?['name'] as String? ??
        _mapFromData(item?['translated_name'])?['name'] as String?;
    if (directName != null && directName.trim().isNotEmpty) {
      return directName.trim();
    }

    return null;
  }

  Future<dynamic> _getSurahTafsirFromQuranFoundation(
    QuranApiConfig config, {
    required int tafsirId,
    required int surahNumber,
  }) async {
    final response = await _quranFoundationGet(
      '/tafsirs/$tafsirId/by_chapter/$surahNumber',
      config: config,
    );

    if (response.statusCode == null || response.statusCode! >= 300) {
      return null;
    }

    return response.data;
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

  Future<int> _resolvePreferredQuranFoundationTafsirId(
    QuranApiConfig config, {
    required int fallbackTafsirId,
  }) async {
    if (!config.usesQuranFoundation) {
      return fallbackTafsirId;
    }

    _invalidateTafsirCacheIfNeeded(config);
    final cached = _preferredEnglishTafsirId;
    if (cached != null && cached > 0) {
      return cached;
    }

    final resources = await listTafsirResources();
    final englishResources = resources
        .where((resource) => resource.isEnglish)
        .toList(growable: false)
      ..sort((left, right) {
        final scoreCompare =
            right.englishPreferenceScore.compareTo(left.englishPreferenceScore);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return left.id.compareTo(right.id);
      });

    final resolved = englishResources.isNotEmpty
        ? englishResources.first.id
        : fallbackTafsirId;
    _preferredEnglishTafsirId = resolved;
    return resolved;
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

  Future<Response<dynamic>> _quranFoundationSearchGet(
    String path, {
    required QuranApiConfig config,
    Map<String, dynamic>? queryParameters,
  }) {
    final headers = _quranFoundationHeaders(config);
    return _dio.get(
      '${config.quranFoundationSearchBaseUrl}$path',
      queryParameters: queryParameters,
      options: headers.isEmpty ? null : Options(headers: headers),
    );
  }

  // ── Tafsir ──

  Future<String?> getVerseTafsir(
    int surahNumber,
    int ayahNumber, {
    int tafsirId = _defaultQuranFoundationTafsirId,
  }) async {
    if (!_isValidVerseReference(surahNumber, ayahNumber)) {
      debugPrint('QuranAPI: Invalid tafsir verse reference $surahNumber:$ayahNumber');
      return null;
    }

    final verseKey = '$surahNumber:$ayahNumber';
    final config = await _getConfig();

    if (config.usesQuranFoundation) {
      try {
        final resolvedTafsirId = await _resolvePreferredQuranFoundationTafsirId(
          config,
          fallbackTafsirId: tafsirId,
        );
        final response = await _quranFoundationGet(
          '/tafsirs/$resolvedTafsirId/by_ayah/$verseKey',
          config: config,
        );

        if (response.statusCode != null && response.statusCode! < 300) {
          final tafsirText = _cleanTafsirTextFromQuranFoundation(
            response.data,
            ayahNumber: ayahNumber,
          );
          if (tafsirText != null) {
            return tafsirText;
          }
        }

        final surahTafsir = await _getSurahTafsirFromQuranFoundation(
          config,
          tafsirId: resolvedTafsirId,
          surahNumber: surahNumber,
        );
        final surahTafsirText = _cleanTafsirTextFromQuranFoundation(
          surahTafsir,
          ayahNumber: ayahNumber,
        );
        if (surahTafsirText != null) {
          return surahTafsirText;
        }
      } catch (e) {
        debugPrint('QuranAPI: Quran Foundation tafsir fetch failed for $verseKey: $e');
      }

      return null;
    }

    try {
      final response = await _alQuranCloudGet(
        '/ayah/$verseKey/ar.muyassar',
      );

      if (response.statusCode == 404) {
        return null;
      }

      final data = _mapFromData(response.data);
      if (data?['code'] != 200) {
        return null;
      }

      return _cleanText(_mapFromData(data?['data'])?['text']);
    } catch (e) {
      debugPrint('QuranAPI: Failed to fetch fallback tafsir for $verseKey: $e');
      return null;
    }
  }

  Future<String?> getVerseTafsirSource(
    int surahNumber,
    int ayahNumber, {
    int tafsirId = _defaultQuranFoundationTafsirId,
  }) async {
    if (!_isValidVerseReference(surahNumber, ayahNumber)) {
      return null;
    }

    final verseKey = '$surahNumber:$ayahNumber';
    final config = await _getConfig();

    if (config.usesQuranFoundation) {
      try {
        final resolvedTafsirId = await _resolvePreferredQuranFoundationTafsirId(
          config,
          fallbackTafsirId: tafsirId,
        );
        final response = await _quranFoundationGet(
          '/tafsirs/$resolvedTafsirId/by_ayah/$verseKey',
          config: config,
        );

        if (response.statusCode != null && response.statusCode! < 300) {
          final source = _tafsirSourceNameFromQuranFoundation(
            response.data,
            ayahNumber: ayahNumber,
          );
          if (source != null) {
            return source;
          }
        }

        final surahTafsir = await _getSurahTafsirFromQuranFoundation(
          config,
          tafsirId: resolvedTafsirId,
          surahNumber: surahNumber,
        );
        final source = _tafsirSourceNameFromQuranFoundation(
          surahTafsir,
          ayahNumber: ayahNumber,
        );
        if (source != null) {
          return source;
        }
      } catch (_) {
        return null;
      }

      return null;
    }

    return 'Tafsir Al-Muyassar';
  }

  int? _maxAyahsForSurah(int surahNumber) {
    if (surahNumber < 1 || surahNumber > _ayahCountsBySurah.length) {
      return null;
    }
    return _ayahCountsBySurah[surahNumber - 1];
  }

  bool _isValidVerseReference(int surahNumber, int ayahNumber) {
    final maxAyahs = _maxAyahsForSurah(surahNumber);
    return maxAyahs != null && ayahNumber >= 1 && ayahNumber <= maxAyahs;
  }

  // ── Verse Retrieval ──

  Future<ChapterInfo?> getChapterInfo(int surahNumber) async {
    if (_maxAyahsForSurah(surahNumber) == null) {
      debugPrint('QuranAPI: Invalid chapter info request for surah $surahNumber');
      return null;
    }

    final config = await _getConfig();
    if (!config.usesQuranFoundation) {
      return null;
    }

    try {
      final response = await _quranFoundationGet(
        '/chapters/$surahNumber/info',
        config: config,
        queryParameters: const <String, dynamic>{
          'language': 'en',
        },
      );

      if (response.statusCode == 404) {
        return null;
      }

      final data = _mapFromData(response.data);
      final chapterInfo = _mapFromData(data?['chapter_info']);
      if (chapterInfo != null) {
        return _chapterInfoFromQuranFoundation(data!);
      }
    } catch (e) {
      debugPrint('QuranAPI: Quran Foundation chapter info fetch failed for $surahNumber: $e');
    }

    return null;
  }

  Future<Verse?> getVerse(int surahNumber, int ayahNumber) async {
    if (!_isValidVerseReference(surahNumber, ayahNumber)) {
      debugPrint('QuranAPI: Invalid verse reference $surahNumber:$ayahNumber');
      return null;
    }

    final config = await _getConfig();
    final verseKey = '$surahNumber:$ayahNumber';

    if (config.usesQuranFoundation) {
      try {
        final response = await _quranFoundationGet(
          '/verses/by_key/$verseKey',
          config: config,
          queryParameters: <String, dynamic>{
            'language': 'en',
            'translations': config.translationId.toString(),
            'audio': config.recitationId,
            'fields': 'text_uthmani',
          },
        );

        if (response.statusCode == 404) {
          return null;
        }

        final data = _mapFromData(response.data);
        final verseJson = _mapFromData(data?['verse']);
        if (verseJson != null) {
          return _verseFromQuranFoundation(data!);
        }
      } catch (e) {
        debugPrint('QuranAPI: Quran Foundation verse fetch failed for $verseKey, falling back: $e');
      }
    }

    try {
      final response = await _alQuranCloudGet(
        '/ayah/$surahNumber:$ayahNumber/editions/quran-uthmani,en.sahih',
      );

      if (response.statusCode == 404) return null;
      final data = _mapFromData(response.data);
      if (data?['code'] != 200) return null;

      final editions = _listFromData(data?['data']);
      if (editions.isEmpty) return null;

      final arabic = editions[0] as Map<String, dynamic>;
      final english = editions.length > 1 ? editions[1] as Map<String, dynamic> : arabic;

      return Verse(
        verseKey: '$surahNumber:$ayahNumber',
        surahNumber: surahNumber,
        ayahNumber: ayahNumber,
        arabicText: arabic['text'] as String?,
        translationText: english['text'] as String?,
        audioUrl: arabic['audio'] as String?,
      );
    } catch (e) {
      debugPrint('QuranAPI: Failed to fetch verse $surahNumber:$ayahNumber: $e');
      return null;
    }
  }

  Future<List<Verse>> getSurahVerses(int surahNumber) async {
    final config = await _getConfig();

    if (config.usesQuranFoundation) {
      try {
        final verses = <Verse>[];
        int page = 1;
        int totalPages = 1;

        do {
          final response = await _quranFoundationGet(
            '/verses/by_chapter/$surahNumber',
            config: config,
            queryParameters: <String, dynamic>{
              'language': 'en',
              'translations': config.translationId.toString(),
              'audio': config.recitationId,
              'fields': 'text_uthmani',
              'page': page,
              'per_page': 50,
            },
          );

          final data = _mapFromData(response.data);
          final pageVerses = _listFromData(data?['verses']);
          final pagination = _mapFromData(data?['pagination']);
          totalPages = pagination?['total_pages'] as int? ?? 1;

          for (final item in pageVerses) {
            final verseJson = _mapFromData(item);
            if (verseJson != null) {
              verses.add(_verseFromQuranFoundation(verseJson));
            }
          }

          page += 1;
        } while (page <= totalPages);

        if (verses.isNotEmpty) {
          return verses;
        }
      } catch (e) {
        debugPrint('QuranAPI: Quran Foundation surah fetch failed for $surahNumber, falling back: $e');
      }
    }

    try {
      final response = await _alQuranCloudGet(
        '/surah/$surahNumber/editions/quran-uthmani,en.sahih',
      );

      final data = _mapFromData(response.data);
      if (data?['code'] != 200) return [];

      final editions = _listFromData(data?['data']);
      if (editions.isEmpty) return [];

      final arabicAyahs = (editions[0]['ayahs'] as List?) ?? [];
      final englishAyahs = editions.length > 1
          ? (editions[1]['ayahs'] as List?) ?? []
          : arabicAyahs;

      final verses = <Verse>[];
      for (int i = 0; i < arabicAyahs.length; i++) {
        final ar = arabicAyahs[i] as Map<String, dynamic>;
        final en = i < englishAyahs.length
            ? englishAyahs[i] as Map<String, dynamic>
            : ar;

        verses.add(Verse(
          verseKey: '$surahNumber:${ar['numberInSurah']}',
          surahNumber: surahNumber,
          ayahNumber: ar['numberInSurah'] as int,
          arabicText: ar['text'] as String?,
          translationText: en['text'] as String?,
          audioUrl: ar['audio'] as String?,
        ));
      }
      return verses;
    } catch (e) {
      debugPrint('QuranAPI: Failed to fetch surah $surahNumber: $e');
      return [];
    }
  }

  // ── Surah List ──

  Future<List<Surah>> listSurahs() async {
    final config = await _getConfig();

    if (config.usesQuranFoundation) {
      try {
        final response = await _quranFoundationGet(
          '/chapters',
          config: config,
          queryParameters: const <String, dynamic>{'language': 'en'},
        );
        final data = _mapFromData(response.data);
        final chapters = _listFromData(data?['chapters']);
        return chapters
            .map((chapter) => Surah.fromJson((chapter as Map).cast<String, dynamic>()))
            .toList();
      } catch (e) {
        debugPrint('QuranAPI: Quran Foundation surah list failed, falling back: $e');
      }
    }

    try {
      final response = await _alQuranCloudGet('/surah');
      final data = _mapFromData(response.data);
      if (data?['code'] != 200) return [];

      final surahs = _listFromData(data?['data']);
      return surahs.map((j) => Surah.fromJson((j as Map).cast<String, dynamic>())).toList();
    } catch (e) {
      debugPrint('QuranAPI: Failed to list surahs: $e');
      return [];
    }
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
          .map((item) => QuranTranslationResource.fromJson(
                (item as Map).cast<String, dynamic>(),
              ))
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
          .map((item) => QuranRecitationResource.fromJson(
                (item as Map).cast<String, dynamic>(),
              ))
          .where((item) => item.id > 0)
          .toList(growable: false);
    } catch (e) {
      debugPrint('QuranAPI: Failed to list recitation resources: $e');
      return const [];
    }
  }

  // ── Search ──

  Future<List<Verse>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return [];
    }

    final config = await _getConfig();

    if (config.usesQuranFoundation) {
      try {
        final response = await _quranFoundationSearchGet(
          '/v1/search',
          config: config,
          queryParameters: <String, dynamic>{
            'mode': 'quick',
            'query': trimmed,
            'versesResultsNumber': 8,
            'navigationalResultsNumber': 5,
            'translation_ids': config.translationId.toString(),
            'get_text': '1',
            'highlight': '0',
            'indexes': 'quran,translations',
          },
        );

        if (response.statusCode != null && response.statusCode! < 300) {
          final data = _mapFromData(response.data);
          final result = _mapFromData(data?['result']);
          final matches = _listFromData(result?['verses']);
          final verses = <Verse>[];

          for (final match in matches) {
            final map = _mapFromData(match);
            final verseKey = map?['key'] as String?;
            if (verseKey == null || verseKey.isEmpty) {
              continue;
            }

            final parts = verseKey.split(':');
            if (parts.length != 2) {
              continue;
            }

            final surahNumber = int.tryParse(parts[0]);
            final ayahNumber = int.tryParse(parts[1]);
            if (surahNumber == null || ayahNumber == null) {
              continue;
            }

            verses.add(Verse(
              verseKey: verseKey,
              surahNumber: surahNumber,
              ayahNumber: ayahNumber,
              translationText: map?['name'] as String?,
            ));
          }

          if (verses.isNotEmpty) {
            return verses;
          }
        }
      } catch (e) {
        debugPrint('QuranAPI: Quran Foundation search failed, falling back: $e');
      }
    }

    final encodedQuery = Uri.encodeComponent(trimmed);

    try {
      final response = await _alQuranCloudGet('/search/$encodedQuery/all/en.sahih');
      final data = _mapFromData(response.data);
      if (data?['code'] != 200) return [];

      final matches = _listFromData(data?['data']?['matches']);
      return matches.map((m) {
        final map = m as Map<String, dynamic>;
        final surah = map['surah'] as Map<String, dynamic>?;
        return Verse(
          verseKey: '${surah?['number']}:${map['numberInSurah']}',
          surahNumber: surah?['number'] as int? ?? 0,
          ayahNumber: map['numberInSurah'] as int? ?? 0,
          translationText: map['text'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('QuranAPI: Search failed: $e');
      return [];
    }
  }

  // ── Audio ──

  Future<String?> getAudioUrl(int surahNumber, int ayahNumber) async {
    if (!_isValidVerseReference(surahNumber, ayahNumber)) {
      debugPrint('QuranAPI: Invalid audio verse reference $surahNumber:$ayahNumber');
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
        debugPrint('QuranAPI: Quran Foundation audio fetch failed for $verseKey, falling back: $e');
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

  // ── Random Verse (for Daily Ayah) ──

  Future<Verse?> getRandomVerse() async {
    final config = await _getConfig();

    if (config.usesQuranFoundation) {
      try {
        final response = await _quranFoundationGet(
          '/verses/random',
          config: config,
          queryParameters: <String, dynamic>{
            'language': 'en',
            'translations': config.translationId.toString(),
            'audio': config.recitationId,
            'fields': 'text_uthmani',
          },
        );
        final data = _mapFromData(response.data);
        final verseJson = _mapFromData(data?['verse']);
        if (verseJson != null) {
          return _verseFromQuranFoundation(data!);
        }
      } catch (e) {
        debugPrint('QuranAPI: Quran Foundation random verse failed, falling back: $e');
      }
    }

    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year, 1, 1))
        .inDays;
    final surah = (dayOfYear * 7 + 13) % 114 + 1;
    final maxAyahs = _maxAyahsForSurah(surah) ?? 1;
    final ayah = (dayOfYear * 3 + 5) % maxAyahs + 1;

    return getVerse(surah, ayah);
  }
}
