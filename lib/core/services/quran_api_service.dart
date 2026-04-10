import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/chapter_info.dart';
import '../models/quran_recitation_resource.dart';
import '../models/quran_tafsir_resource.dart';
import '../models/quran_translation_resource.dart';
import '../models/verse.dart';
import '../models/surah.dart';
import 'local_quran_asset_service.dart';
import 'quran_api_config_service.dart';

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
    int tafsirId = _defaultQuranFoundationTafsirId,
  }) async {
    if (!_isValidVerseReference(surahNumber, ayahNumber)) {
      debugPrint(
        'QuranAPI: Invalid tafsir verse reference $surahNumber:$ayahNumber',
      );
      return null;
    }

    return LocalQuranAssetService.instance.getVerseTafsir(
      surahNumber,
      ayahNumber,
    );
  }

  Future<String?> getVerseTafsirSource(
    int surahNumber,
    int ayahNumber, {
    int tafsirId = _defaultQuranFoundationTafsirId,
  }) async {
    if (!_isValidVerseReference(surahNumber, ayahNumber)) {
      return null;
    }

    return LocalQuranAssetService.instance.getVerseTafsirSource(
      surahNumber,
      ayahNumber,
    );
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
    if (_maxAyahsForSurah(surahNumber) == null) {
      debugPrint(
        'QuranAPI: Invalid chapter info request for surah $surahNumber',
      );
      return null;
    }
    return null;
  }

  Future<Verse?> getVerse(int surahNumber, int ayahNumber) async {
    if (!_isValidVerseReference(surahNumber, ayahNumber)) {
      debugPrint('QuranAPI: Invalid verse reference $surahNumber:$ayahNumber');
      return null;
    }

    return LocalQuranAssetService.instance.getVerse(surahNumber, ayahNumber);
  }

  Future<List<Verse>> getSurahVerses(int surahNumber) async {
    if (_maxAyahsForSurah(surahNumber) == null) {
      return const <Verse>[];
    }

    return LocalQuranAssetService.instance.getSurahVerses(surahNumber);
  }

  // ── Surah List ──

  Future<List<Surah>> listSurahs() async {
    return LocalQuranAssetService.instance.listSurahs();
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

  // ── Search ──

  Future<List<Verse>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return [];
    }

    return LocalQuranAssetService.instance.search(trimmed);
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
    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year, 1, 1))
        .inDays;
    final surah = (dayOfYear * 7 + 13) % 114 + 1;
    final maxAyahs = _maxAyahsForSurah(surah) ?? 1;
    final ayah = (dayOfYear * 3 + 5) % maxAyahs + 1;

    return getVerse(surah, ayah);
  }
}
