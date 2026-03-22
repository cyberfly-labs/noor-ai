import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'embedding_service.dart';
import 'model_manager.dart';
import 'native_bridge.dart';
import '../utils/perf_trace.dart';

/// Vector store backed by native edgemind/zvec on Android, with in-memory fallback.
class VectorStoreService {
  VectorStoreService._();
  static final VectorStoreService instance = VectorStoreService._();

  /// In-memory fallback entries (non-Android or zvec init failure).
  final List<VectorEntry> _entries = [];
  bool _initialized = false;

  bool _nativeAvailable = false;
  bool _nativeRuntimeInitialized = false;
  Future<void>? _seedDocumentsFuture;

  static const String _emotionalSeedFlag =
      'vector_store.native.emotional_seed.v1';
  static const String _corpusSeedFlag = 'vector_store.native.corpus_seed.v1';
  static const String _bundledDbManifestPath =
      'assets/vector_db/manifest.json';
  static const String _bundledDbVersionKey =
      'vector_store.native.asset_db.version';

  bool get isInitialized => _initialized;
  int get entryCount => _entries.length;

  bool get usesNativeZvec => _nativeAvailable;

  Future<bool> hasReadyNativeCorpus() async {
    if (!Platform.isAndroid) {
      return false;
    }

    await ModelManager.instance.initialize();
    final prefs = await SharedPreferences.getInstance();
    final dbDir = Directory('${ModelManager.instance.modelsPath}/zvec_db');
    return prefs.getBool(_corpusSeedFlag) == true && await dbDir.exists();
  }

  Future<void> initialize() async {
    if (_initialized) return;

    await EmbeddingService.instance.initialize();

    if (Platform.isAndroid) {
      await _restoreBundledNativeDbIfAvailable();
      _nativeAvailable = await _ensureNativeRuntimeInitialized();
    }

    _initialized = true;
    if (_nativeAvailable) {
      debugPrint('VectorStore: Initialized (native edgemind zvec)');
    } else {
      debugPrint('VectorStore: Initialized (in-memory fallback)');
    }
  }

  // ── Insert ──

  void insert({
    required String id,
    required String content,
    required List<double> vector,
    Map<String, String>? metadata,
  }) {
    if (_nativeAvailable) {
      try {
        final inserted = NativeBridge.instance.addPagedDocument(
          jsonEncode(<Map<String, String>>[
            <String, String>{'text': content},
          ]),
          jsonEncode(<String, String>{
            'hash': id,
            ...?metadata,
          }),
        );
        if (inserted != null) {
          return;
        }
      } catch (e) {
        debugPrint('VectorStore: native insert failed, using fallback: $e');
      }
    }

    _entries.removeWhere((e) => e.id == id);
    _entries.add(VectorEntry(
      id: id,
      content: content,
      vector: vector,
      metadata: metadata ?? {},
    ));
  }

  // ── Query ──

  List<VectorSearchResult> query(
    List<double> queryVector, {
    int topK = 5,
    bool Function(VectorEntry entry)? filter,
  }) {
    final candidates = filter == null
        ? _entries
        : _entries.where(filter).toList(growable: false);
    if (candidates.isEmpty) return [];

    final scored = candidates.map((entry) {
      final score = _cosineSimilarity(queryVector, entry.vector);
      return VectorSearchResult(entry: entry, score: score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList();
  }

  /// Query by text — embeds then searches via zvec or in-memory fallback.
  List<VectorSearchResult> queryByText(
    String text, {
    int topK = 5,
    bool Function(VectorEntry entry)? filter,
  }) {
    final traceTag = PerfTrace.nextTag('vector.queryByText');
    final totalSw = PerfTrace.start(traceTag, 'query');

    if (_nativeAvailable) {
      final nativeSw = Stopwatch()..start();
      final results = _nativeSearch(text, topK: topK, filter: filter);
      if (results != null) {
        PerfTrace.mark(traceTag, 'native_search', nativeSw);
        PerfTrace.end(traceTag, 'query', totalSw);
        return results;
      }
      PerfTrace.mark(traceTag, 'native_search_fallback', nativeSw);
    }

    final embedSw = Stopwatch()..start();
    final vector = EmbeddingService.instance.embed(text, isQuery: true);
    PerfTrace.mark(traceTag, 'embed', embedSw);
    final searchSw = Stopwatch()..start();
    final results = query(vector, topK: topK, filter: filter);
    PerfTrace.mark(traceTag, 'in_memory_search', searchSw);
    PerfTrace.end(traceTag, 'query', totalSw);
    return results;
  }

  List<VectorSearchResult> searchInDocument(
    String documentId,
    String query, {
    int limit = 1,
  }) {
    if (_nativeAvailable) {
      final results = _nativeSearchInDocument(documentId, query, topK: limit);
      if (results != null) {
        return results;
      }
    }

    final vector = EmbeddingService.instance.embed(query, isQuery: true);
    return this.query(
      vector,
      topK: limit,
      filter: (entry) =>
          entry.metadata['hash'] == documentId || entry.id == documentId,
    );
  }

  // ── Seeding ──

  Future<void> seedEmotionalVerses(List<EmotionalVerse> verses) async {
    if (!_initialized) {
      await initialize();
    }

    if (_nativeAvailable) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_emotionalSeedFlag) == true) {
        debugPrint('VectorStore: Skipping emotional seed - already imported');
        return;
      }

      var seeded = 0;
      for (final verse in verses) {
        final inserted = NativeBridge.instance.addPagedDocument(
          jsonEncode(<Map<String, String>>[
            <String, String>{'text': verse.translationText},
          ]),
          jsonEncode(<String, String>{
            'hash': 'emotion_${verse.verseKey}',
            'kind': 'emotional',
            'verse_key': verse.verseKey,
            'emotion': verse.emotion,
          }),
        );
        if (inserted != null) {
          seeded += 1;
        }
        await Future<void>.delayed(Duration.zero);
      }

      if (seeded == verses.length) {
        await prefs.setBool(_emotionalSeedFlag, true);
      }
      debugPrint('VectorStore: Seeded $seeded emotional verses (native)');
      return;
    }

    for (final verse in verses) {
      final vector = EmbeddingService.instance.embed(
        '${verse.emotion} ${verse.translationText}',
      );
      insert(
        id: 'emotion_${verse.verseKey}',
        content: verse.translationText,
        vector: vector,
        metadata: {
          'kind': 'emotional',
          'verse_key': verse.verseKey,
          'emotion': verse.emotion,
        },
      );
    }
    debugPrint('VectorStore: Seeded ${verses.length} emotional verses');
  }

  Future<void> seedDocuments(Iterable<VectorSeedDocument> documents) async {
    final pending = _seedDocumentsFuture;
    if (pending != null) {
      await pending;
      return;
    }

    final future = _seedDocumentsInternal(documents);
    _seedDocumentsFuture = future;
    try {
      await future;
    } finally {
      if (identical(_seedDocumentsFuture, future)) {
        _seedDocumentsFuture = null;
      }
    }
  }

  Future<void> _seedDocumentsInternal(
    Iterable<VectorSeedDocument> documents,
  ) async {
    if (!_initialized) {
      await initialize();
    }

    final docList = documents.toList(growable: false);

    if (_nativeAvailable) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_corpusSeedFlag) == true) {
        debugPrint('VectorStore: Skipping corpus seed - already imported');
        return;
      }
    }

    var count = 0;
    const batchSize = 8;
    for (var i = 0; i < docList.length; i += batchSize) {
      final batch = docList.sublist(
        i,
        (i + batchSize).clamp(0, docList.length),
      );

      if (_nativeAvailable) {
        for (final document in batch) {
          try {
            final inserted = NativeBridge.instance.addPagedDocument(
              jsonEncode(<Map<String, String>>[
                <String, String>{'text': document.content},
              ]),
              jsonEncode(<String, String>{
                'hash': document.id,
                ...document.metadata,
              }),
            );
            if (inserted != null) {
              count += 1;
            }
          } catch (e) {
            debugPrint('VectorStore: native insert failed for ${document.id}: $e');
          }
        }

        await Future<void>.delayed(Duration.zero);
        continue;
      }

      // Fallback: in-memory
      for (final document in batch) {
        final vector = EmbeddingService.instance.embed(document.content);
        _entries.removeWhere((e) => e.id == document.id);
        _entries.add(VectorEntry(
          id: document.id,
          content: document.content,
          vector: vector,
          metadata: document.metadata,
        ));
        count += 1;
      }

      await Future<void>.delayed(Duration.zero);
    }

    if (_nativeAvailable) {
      final prefs = await SharedPreferences.getInstance();
      if (count == docList.length) {
        await prefs.setBool(_corpusSeedFlag, true);
      }
    }

    debugPrint(
      'VectorStore: Seeded $count corpus documents '
      '(${_nativeAvailable ? "native" : "in-memory"})',
    );
  }

  void clear() {
    _entries.clear();
  }

  // ── Private helpers ──

  Future<bool> _ensureNativeRuntimeInitialized() async {
    if (_nativeRuntimeInitialized) {
      return true;
    }

    if (!NativeBridge.instance.isAvailable) {
      return false;
    }

    try {
      await ModelManager.instance.initialize();
      final configJson = jsonEncode(<String, Object>{
        'data_dir': ModelManager.instance.modelPath(ModelType.llm),
        'models': <String, String>{
          'embedding_path': ModelManager.instance.modelPath(ModelType.embedding),
          'whisper_dir': ModelManager.instance.modelPath(ModelType.asr),
        },
        'storage': <String, String>{
          'db_path': '${ModelManager.instance.modelsPath}/zvec_db',
        },
        'startup': <String, bool>{
          'prewarm_engines': false,
        },
      });

      final result = NativeBridge.instance.initialize(configJson);
      _nativeRuntimeInitialized = result.isSuccess;
      if (!_nativeRuntimeInitialized) {
        debugPrint(
          'VectorStore: Native runtime init failed '
          '(code=${result.errorCode}): ${result.error ?? "unknown error"}',
        );
      }
      return _nativeRuntimeInitialized;
    } catch (e) {
      debugPrint('VectorStore: Native runtime init threw: $e');
      return false;
    }
  }

  Future<void> _restoreBundledNativeDbIfAvailable() async {
    try {
      final rawManifest = await rootBundle.loadString(_bundledDbManifestPath);
      final decoded = jsonDecode(rawManifest);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final rawFiles = decoded['files'];
      if (rawFiles is! List || rawFiles.isEmpty) {
        return;
      }

      final files = rawFiles
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (files.isEmpty) {
        return;
      }

      final requiredFiles = files
          .where((path) => !_isTransientBundledDbFile(path))
          .toList(growable: false);

      final version = (decoded['version'] ?? '').toString();
      final prefs = await SharedPreferences.getInstance();
      await ModelManager.instance.initialize();
      final restoreRoot = Directory(ModelManager.instance.modelsPath);
      final dbDir = Directory('${ModelManager.instance.modelsPath}/zvec_db');
      final dbDirExists = await dbDir.exists();

      if (dbDirExists) {
        await _deleteTransientLockFiles(dbDir);
      }

      final allFilesRestored = await Future.wait(
        requiredFiles.map((relativePath) async {
          final targetPath = p.normalize(p.join(restoreRoot.path, relativePath));
          final file = File(targetPath);
          if (!await file.exists()) {
            return false;
          }

          final length = await file.length();
          return length > 0;
        }),
      );

      if (version.isNotEmpty &&
          prefs.getString(_bundledDbVersionKey) == version &&
          dbDirExists &&
          !await _containsTransientLockFiles(dbDir) &&
          allFilesRestored.every((exists) => exists)) {
        return;
      }

      if (dbDirExists) {
        await dbDir.delete(recursive: true);
      }
      await restoreRoot.create(recursive: true);

      final sidecarPrefix = '${dbDir.path}_';
      final existingSidecars = await restoreRoot
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .where((file) => file.path.startsWith(sidecarPrefix))
          .toList();
      for (final sidecar in existingSidecars) {
        await sidecar.delete();
      }

      for (final relativePath in files) {
        if (_isTransientBundledDbFile(relativePath)) {
          continue;
        }
        final assetPath = 'assets/vector_db/$relativePath';
        final bytes = await rootBundle.load(assetPath);
        final targetFile = File(p.normalize(p.join(restoreRoot.path, relativePath)));
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
      }

      await _deleteTransientLockFiles(dbDir);

      if (version.isNotEmpty) {
        await prefs.setString(_bundledDbVersionKey, version);
      }
      await prefs.setBool(_emotionalSeedFlag, true);
      await prefs.setBool(_corpusSeedFlag, true);
      debugPrint(
        'VectorStore: Restored bundled vector DB '
        '(${requiredFiles.length} files, skipped ${files.length - requiredFiles.length} transient)',
      );
    } on FlutterError {
      // Bundled vector DB is optional.
    } catch (e) {
      debugPrint('VectorStore: Bundled DB restore skipped: $e');
    }
  }

  bool _isTransientBundledDbFile(String relativePath) {
    final normalized = p.posix.normalize(relativePath).toLowerCase();
    return p.posix.basename(normalized) == 'lock';
  }

  Future<void> _deleteTransientLockFiles(Directory dbDir) async {
    if (!await dbDir.exists()) {
      return;
    }

    await for (final entity in dbDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (p.basename(entity.path).toLowerCase() != 'lock') {
        continue;
      }
      try {
        await entity.delete();
      } catch (e) {
        debugPrint('VectorStore: Failed to delete transient lock ${entity.path}: $e');
      }
    }
  }

  Future<bool> _containsTransientLockFiles(Directory dbDir) async {
    if (!await dbDir.exists()) {
      return false;
    }

    await for (final entity in dbDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (p.basename(entity.path).toLowerCase() == 'lock') {
        return true;
      }
    }

    return false;
  }

  List<VectorSearchResult>? _nativeSearch(
    String text, {
    int topK = 5,
    bool Function(VectorEntry entry)? filter,
  }) {
    final raw = NativeBridge.instance.searchKnowledge(
      text,
      limit: filter == null ? topK : max(topK * 6, topK),
    );
    if (raw == null || raw.isEmpty || raw == '[]') {
      return null;
    }

    return _decodeNativeSearchResults(raw, topK: topK, filter: filter);
  }

  List<VectorSearchResult>? _nativeSearchInDocument(
    String documentId,
    String query, {
    int topK = 1,
  }) {
    final raw = NativeBridge.instance.searchInDocument(
      documentId,
      query,
      limit: topK,
    );
    if (raw == null || raw.isEmpty || raw == '[]') {
      return null;
    }

    return _decodeNativeSearchResults(raw, topK: topK);
  }

  List<VectorSearchResult>? _decodeNativeSearchResults(
    String raw, {
    required int topK,
    bool Function(VectorEntry entry)? filter,
  }) {
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.isEmpty) {
      return null;
    }

    final results = <VectorSearchResult>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final content = item['content'] as String? ?? '';
      final metadata = <String, String>{};
      final rawMeta = item['metadata'];
      if (rawMeta is Map) {
        for (final entry in rawMeta.entries) {
          final value = entry.value;
          if (value != null && value.toString().isNotEmpty) {
            metadata[entry.key.toString()] = value.toString();
          }
        }
      }

      final entry = VectorEntry(
        id: item['chunk_id'] as String? ?? item['doc_id'] as String? ?? '',
        content: content,
        vector: const <double>[],
        metadata: metadata,
      );

      if (filter != null && !filter(entry)) {
        continue;
      }

      results.add(VectorSearchResult(
        entry: entry,
        score: (item['score'] as num?)?.toDouble() ?? 0.0,
      ));

      if (results.length >= topK) {
        break;
      }
    }

    return results.isEmpty ? null : results;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0) return 0.0;
    return dotProduct / denominator;
  }
}

class VectorEntry {
  final String id;
  final String content;
  final List<double> vector;
  final Map<String, String> metadata;

  const VectorEntry({
    required this.id,
    required this.content,
    required this.vector,
    this.metadata = const {},
  });
}

class VectorSearchResult {
  final VectorEntry entry;
  final double score;

  const VectorSearchResult({required this.entry, required this.score});
}

class VectorSeedDocument {
  final String id;
  final String content;
  final Map<String, String> metadata;

  const VectorSeedDocument({
    required this.id,
    required this.content,
    this.metadata = const <String, String>{},
  });
}

class EmotionalVerse {
  final String verseKey;
  final String emotion;
  final String translationText;
  final String? arabicText;

  const EmotionalVerse({
    required this.verseKey,
    required this.emotion,
    required this.translationText,
    this.arabicText,
  });
}

/// Pre-defined emotional verses for seeding the vector store
const kEmotionalVerses = <EmotionalVerse>[
  EmotionalVerse(
    verseKey: '2:286',
    emotion: 'anxiety worry stress overwhelmed',
    translationText: 'Allah does not burden a soul beyond that it can bear.',
  ),
  EmotionalVerse(
    verseKey: '94:5',
    emotion: 'sadness difficulty hardship',
    translationText: 'For indeed, with hardship will be ease.',
  ),
  EmotionalVerse(
    verseKey: '94:6',
    emotion: 'sadness difficulty hardship hope',
    translationText: 'Indeed, with hardship will be ease.',
  ),
  EmotionalVerse(
    verseKey: '13:28',
    emotion: 'anxiety peace calm heart',
    translationText: 'Verily, in the remembrance of Allah do hearts find rest.',
  ),
  EmotionalVerse(
    verseKey: '2:153',
    emotion: 'patience struggle endurance',
    translationText: 'O you who have believed, seek help through patience and prayer. Indeed, Allah is with the patient.',
  ),
  EmotionalVerse(
    verseKey: '3:139',
    emotion: 'sadness weakness defeat',
    translationText: 'So do not weaken and do not grieve, and you will be superior if you are believers.',
  ),
  EmotionalVerse(
    verseKey: '65:3',
    emotion: 'trust reliance uncertainty',
    translationText: 'And whoever relies upon Allah - then He is sufficient for him.',
  ),
  EmotionalVerse(
    verseKey: '39:53',
    emotion: 'hopeless despair sin guilt',
    translationText: 'Say, O My servants who have transgressed against themselves, do not despair of the mercy of Allah. Indeed, Allah forgives all sins.',
  ),
  EmotionalVerse(
    verseKey: '2:216',
    emotion: 'confusion understanding wisdom',
    translationText: 'Perhaps you hate a thing and it is good for you; and perhaps you love a thing and it is bad for you. And Allah knows, while you know not.',
  ),
  EmotionalVerse(
    verseKey: '9:40',
    emotion: 'fear lonely alone',
    translationText: 'Do not grieve; indeed Allah is with us.',
  ),
  EmotionalVerse(
    verseKey: '3:173',
    emotion: 'fear trust safety',
    translationText: 'Sufficient for us is Allah, and He is the best Disposer of affairs.',
  ),
  EmotionalVerse(
    verseKey: '93:3',
    emotion: 'abandoned forsaken alone lonely',
    translationText: 'Your Lord has not taken leave of you, nor has He detested you.',
  ),
  EmotionalVerse(
    verseKey: '14:7',
    emotion: 'grateful thankful gratitude blessed',
    translationText: 'If you are grateful, I will surely increase you in favor.',
  ),
  EmotionalVerse(
    verseKey: '12:87',
    emotion: 'hopeless despair give up',
    translationText: 'Indeed, no one despairs of relief from Allah except the disbelieving people.',
  ),
  EmotionalVerse(
    verseKey: '2:45',
    emotion: 'struggle patience prayer',
    translationText: 'And seek help through patience and prayer, and indeed, it is difficult except for the humbly submissive.',
  ),
  EmotionalVerse(
    verseKey: '29:2',
    emotion: 'test trial difficulty',
    translationText: 'Do the people think that they will be left to say, We believe and they will not be tested?',
  ),
  EmotionalVerse(
    verseKey: '40:60',
    emotion: 'prayer help need',
    translationText: 'Call upon Me; I will respond to you.',
  ),
  EmotionalVerse(
    verseKey: '8:46',
    emotion: 'patience endurance strength',
    translationText: 'And be patient, for indeed, Allah is with the patient.',
  ),
  EmotionalVerse(
    verseKey: '3:200',
    emotion: 'patience perseverance taqwa',
    translationText: 'O you who have believed, persevere and endure and remain stationed and fear Allah that you may be successful.',
  ),
  EmotionalVerse(
    verseKey: '42:30',
    emotion: 'suffering consequences forgiveness',
    translationText: 'And whatever strikes you of disaster - it is for what your hands have earned; but He pardons much.',
  ),
];
