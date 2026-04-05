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
enum VectorSearchBackend {
  nativeZvec,
  inMemory,
  unknown,
}

class VectorStoreService {
  VectorStoreService._();
  static final VectorStoreService instance = VectorStoreService._();

  /// In-memory fallback entries (non-Android or zvec init failure).
  final List<VectorEntry> _entries = [];
  bool _initialized = false;
  Future<void>? _initializeFuture;

  bool _nativeAvailable = false;
  bool _nativeRuntimeInitialized = false;
  Future<void>? _seedDocumentsFuture;
  Future<void>? _activateNativeFuture;
  VectorSearchBackend _lastQueryBackend = VectorSearchBackend.unknown;
  VectorSearchBackend _lastDocumentQueryBackend = VectorSearchBackend.unknown;

  static const String _emotionalSeedFlag =
      'vector_store.native.emotional_seed.v2';
  static const String _corpusSeedFlag = 'vector_store.native.corpus_seed.v1';
  static const String _androidBuiltCorpusVersionKey =
      'vector_store.native.android_build.version';
  static const String _bundledDbManifestPath =
      'assets/vector_db/manifest.json';
  static const String _bundledDbVersionKey =
      'vector_store.native.asset_db.version';
    static const String _bundledDbRestoreMarkerFileName =
      '.bundled_vector_db_version';
    static const List<String> _bundledDbCriticalRelativePaths = <String>[
      'zvec_db/manifest.131',
      'zvec_db/del.0',
      'zvec_db/0/scalar.0.ipc',
      'zvec_db/0/scalar.index.1.rocksdb/CURRENT',
      'zvec_db/idmap.0/CURRENT',
      'zvec_db_sources.tsv',
      'zvec_db_deleted.txt',
    ];

  bool get isInitialized => _initialized;
  int get entryCount => _entries.length;

  bool get usesNativeZvec => _nativeAvailable;
  VectorSearchBackend get lastQueryBackend => _lastQueryBackend;
  VectorSearchBackend get lastDocumentQueryBackend => _lastDocumentQueryBackend;

  Future<bool> hasReadyNativeCorpus() async {
    if (!Platform.isAndroid) {
      return false;
    }

    await initialize();
    final prefs = await SharedPreferences.getInstance();
    final dbDir = Directory('${ModelManager.instance.modelsPath}/zvec_db');
    if (prefs.getBool(_corpusSeedFlag) != true || !await dbDir.exists()) {
      return false;
    }

    if (!_nativeAvailable) {
      return false;
    }

    final probe = _nativeSearch(
      'hardship ease patience mercy forgiveness guidance',
      topK: 1,
    );
    return probe != null && probe.isNotEmpty;
  }

  Future<bool> ensureAndroidNativeCorpusBuilt({
    required Future<List<VectorSeedDocument>> Function() loadDocuments,
    List<EmotionalVerse> emotionalVerses = const <EmotionalVerse>[],
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }

    await initialize();
    if (!_nativeAvailable) {
      return false;
    }

    if (await hasReadyNativeCorpus()) {
      debugPrint('VectorStore: Native corpus already searchable');
      return true;
    }

    debugPrint('VectorStore: Building native corpus on Android from local assets');

    final documents = await loadDocuments();
    final combinedDocuments = <VectorSeedDocument>[
      ...documents,
      ...emotionalVerses.map(
        (verse) => VectorSeedDocument(
          id: 'emotion_${verse.verseKey}',
          content: verse.translationText,
          metadata: <String, String>{
            'kind': 'emotional',
            'verse_key': verse.verseKey,
            'category': verse.category,
            'emotion': verse.emotion,
          },
        ),
      ),
    ];
    await seedDocuments(combinedDocuments);

    final ready = await hasReadyNativeCorpus();
    if (ready) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_emotionalSeedFlag, true);
    }
    debugPrint(
      'VectorStore: Android native corpus build '
      '${ready ? 'completed' : 'did not produce a searchable corpus'}',
    );
    return ready;
  }

  Future<void> initialize() async {
    if (_initialized) {
      await _maybeActivateNativeRuntime();
      return;
    }

    final pending = _initializeFuture;
    if (pending != null) {
      await pending;
      await _maybeActivateNativeRuntime();
      return;
    }

    final future = _initializeInternal();
    _initializeFuture = future;
    try {
      await future;
      await _maybeActivateNativeRuntime();
    } finally {
      if (identical(_initializeFuture, future)) {
        _initializeFuture = null;
      }
    }
  }

  Future<void> _initializeInternal() async {
    if (_initialized) return;

    await EmbeddingService.instance.initialize();

    if (Platform.isAndroid &&
        await ModelManager.instance.areRagModelsDownloaded()) {
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
        _lastQueryBackend = VectorSearchBackend.nativeZvec;
        _debugLogSearchResults('native', text, results);
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
    _lastQueryBackend = VectorSearchBackend.inMemory;
    _debugLogSearchResults('in-memory', text, results);
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
        _lastDocumentQueryBackend = VectorSearchBackend.nativeZvec;
        return results;
      }
    }

    final vector = EmbeddingService.instance.embed(query, isQuery: true);
    _lastDocumentQueryBackend = VectorSearchBackend.inMemory;
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
        final probe = _nativeSearch(
          'anxiety worry stress hope mercy relief',
          topK: 1,
          filter: (entry) => entry.metadata['kind'] == 'emotional',
        );
        if (probe != null && probe.isNotEmpty) {
          debugPrint('VectorStore: Skipping emotional seed - already imported');
          return;
        }
        debugPrint(
          'VectorStore: Emotional seed flag was set but emotional entries are not searchable. Rebuilding.',
        );
        await prefs.setBool(_emotionalSeedFlag, false);
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
            'category': verse.category,
            'emotion': verse.emotion,
          }),
        );
        if (inserted != null) {
          seeded += 1;
        }
      }

      if (seeded == verses.length) {
        await prefs.setBool(_emotionalSeedFlag, true);
      }
      debugPrint('VectorStore: Seeded $seeded emotional verses (native)');
      return;
    }

    for (final verse in verses) {
      final vector = EmbeddingService.instance.embed(
        '${verse.category} ${verse.emotion} ${verse.translationText}',
      );
      insert(
        id: 'emotion_${verse.verseKey}',
        content: verse.translationText,
        vector: vector,
        metadata: {
          'kind': 'emotional',
          'verse_key': verse.verseKey,
          'category': verse.category,
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
        if (await hasReadyNativeCorpus()) {
          debugPrint('VectorStore: Skipping corpus seed - already imported');
          return;
        }
        debugPrint(
          'VectorStore: Corpus seed flag was set but native corpus is not searchable. Rebuilding.',
        );
        await prefs.setBool(_corpusSeedFlag, false);
      }
    }

    var count = 0;
    const batchSize = 48;
    for (var i = 0; i < docList.length; i += batchSize) {
      final batch = docList.sublist(
        i,
        (i + batchSize).clamp(0, docList.length),
      );

      if (_nativeAvailable) {
        try {
          final payload = jsonEncode(
            batch
                .map((document) => <String, Object>{
                      'content': document.content,
                      'metadata': <String, String>{
                        'hash': document.id,
                        ...document.metadata,
                      },
                    })
                .toList(growable: false),
          );
          final insertedCount = NativeBridge.instance.addDocumentsBulk(payload);
          if (insertedCount != null) {
            count += insertedCount;
          }
        } catch (e) {
          debugPrint('VectorStore: native bulk insert failed for batch at $i: $e');
        }

        if (((i ~/ batchSize) + 1) % 4 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
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

      if (((i ~/ batchSize) + 1) % 4 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (_nativeAvailable) {
      final prefs = await SharedPreferences.getInstance();
      if (count == docList.length) {
        await prefs.setBool(_corpusSeedFlag, true);
        final bundledVersion = await _loadBundledDbVersion();
        if (bundledVersion.isNotEmpty) {
          await prefs.setString(_androidBuiltCorpusVersionKey, bundledVersion);
        }
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

  Future<void> _maybeActivateNativeRuntime() async {
    if (!Platform.isAndroid || _nativeAvailable) {
      return;
    }

    final pending = _activateNativeFuture;
    if (pending != null) {
      await pending;
      return;
    }

    final future = _maybeActivateNativeRuntimeInternal();
    _activateNativeFuture = future;
    try {
      await future;
    } finally {
      if (identical(_activateNativeFuture, future)) {
        _activateNativeFuture = null;
      }
    }
  }

  Future<void> _maybeActivateNativeRuntimeInternal() async {
    if (_nativeAvailable) {
      return;
    }

    await ModelManager.instance.initialize();
    if (!await ModelManager.instance.areRagModelsDownloaded()) {
      return;
    }

    await _restoreBundledNativeDbIfAvailable();
    _nativeAvailable = await _ensureNativeRuntimeInitialized();
    if (_nativeAvailable) {
      debugPrint('VectorStore: Native runtime activated');
    }
  }

  Future<bool> _ensureNativeRuntimeInitialized() async {
    if (_nativeRuntimeInitialized) {
      return true;
    }

    if (!NativeBridge.instance.isAvailable) {
      return false;
    }

    try {
      await ModelManager.instance.initialize();
      if (!await ModelManager.instance.areRagModelsDownloaded()) {
        return false;
      }
      await ModelManager.instance.ensureRuntimeReady(ModelType.embedding);
      await ModelManager.instance.ensureRuntimeReady(ModelType.llm);
      final llmConfigPath = ModelManager.instance.llmRuntimeConfigPath();
      final modelDir = ModelManager.instance.modelPath(ModelType.llm);
      if (llmConfigPath.isEmpty || modelDir.isEmpty) {
        return false;
      }
      final configJson = jsonEncode(<String, Object>{
        'data_dir': modelDir.endsWith('/') ? modelDir : '$modelDir/',
        'models': <String, String>{
          'embedding_path': ModelManager.instance.modelPath(ModelType.embedding),
          'whisper_dir': ModelManager.instance.modelPath(ModelType.asr),
        },
        'storage': <String, String>{
          'db_path': '${ModelManager.instance.modelsPath}/zvec_db',
        },
        'startup': <String, bool>{
          'prewarm_engines': true,
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
      debugPrint('VectorStore: Checking bundled vector DB manifest at $_bundledDbManifestPath');
      final rawManifest = await rootBundle.loadString(_bundledDbManifestPath);
      final decoded = jsonDecode(rawManifest);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('VectorStore: Bundled DB manifest is not a JSON object');
        return;
      }

      final rawFiles = decoded['files'];
      if (rawFiles is! List || rawFiles.isEmpty) {
        debugPrint('VectorStore: Bundled DB manifest has no files');
        return;
      }

      final files = rawFiles
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (files.isEmpty) {
        debugPrint('VectorStore: Bundled DB manifest only contained empty paths');
        return;
      }

      final version = (decoded['version'] ?? '').toString();
      final prefs = await SharedPreferences.getInstance();
      await ModelManager.instance.initialize();
      final restoreRoot = Directory(ModelManager.instance.modelsPath);
      final dbDir = Directory('${ModelManager.instance.modelsPath}/zvec_db');
      final dbDirExists = await dbDir.exists();
      final androidBuiltVersion = prefs.getString(_androidBuiltCorpusVersionKey);
      final savedVersion = prefs.getString(_bundledDbVersionKey) ?? '';
      final markerVersion = await _loadBundledDbRestoreMarkerVersion(restoreRoot);
      debugPrint(
        'VectorStore: Bundled DB manifest version=${version.isEmpty ? '<empty>' : version}, '
        'savedVersion=$savedVersion, markerVersion=$markerVersion, '
        'androidBuiltVersion=$androidBuiltVersion, dbDirExists=$dbDirExists',
      );

      if (version.isNotEmpty &&
          androidBuiltVersion == version &&
          dbDirExists) {
        debugPrint(
          'VectorStore: Skipping bundled restore because an Android-built corpus already exists for version $version',
        );
        return;
      }

      final hasCriticalFootprint =
          await _hasBundledDbCriticalFootprint(restoreRoot);

      if (version.isNotEmpty &&
          dbDirExists &&
          (savedVersion == version || markerVersion == version) &&
          hasCriticalFootprint) {
        if (markerVersion != version) {
          await _writeBundledDbRestoreMarkerVersion(restoreRoot, version);
        }
        debugPrint('VectorStore: Bundled DB already restored for version $version');
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
        final assetPath = 'assets/vector_db/$relativePath';
        debugPrint('VectorStore: Restoring bundled asset $assetPath');
        final bytes = await rootBundle.load(assetPath);
        final targetFile = File(p.normalize(p.join(restoreRoot.path, relativePath)));
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
        if (!await targetFile.exists()) {
          throw FileSystemException(
            'Bundled DB restore did not create expected file',
            targetFile.path,
          );
        }
      }

      final missingFiles = await _missingBundledFiles(restoreRoot, files);
      if (missingFiles.isNotEmpty) {
        throw FileSystemException(
          'Bundled DB restore left missing files (first: ${missingFiles.first})',
          restoreRoot.path,
        );
      }

      if (version.isNotEmpty) {
        await prefs.setString(_bundledDbVersionKey, version);
        await _writeBundledDbRestoreMarkerVersion(restoreRoot, version);
      }
      await prefs.remove(_androidBuiltCorpusVersionKey);
      await prefs.setBool(_emotionalSeedFlag, true);
      await prefs.setBool(_corpusSeedFlag, true);
      debugPrint(
        'VectorStore: Restored bundled vector DB '
        '(${files.length} files)',
      );
    } on FlutterError catch (e) {
      debugPrint('VectorStore: Bundled DB restore FlutterError: $e');
    } catch (e) {
      debugPrint('VectorStore: Bundled DB restore skipped: $e');
    }
  }

  Future<String> _loadBundledDbVersion() async {
    try {
      final rawManifest = await rootBundle.loadString(_bundledDbManifestPath);
      final decoded = jsonDecode(rawManifest);
      if (decoded is! Map<String, dynamic>) {
        return '';
      }
      return (decoded['version'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }


  void _debugLogSearchResults(
    String source,
    String query,
    List<VectorSearchResult> results,
  ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'VectorStore: Search results [$source] query="${query.replaceAll('\n', ' ').trim()}" count=${results.length}',
    );

    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      final content = result.entry.content
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final metadata = result.entry.metadata.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(', ');
      debugPrint(
        'VectorStore: Result ${index + 1} score=${result.score.toStringAsFixed(4)} '
        'id=${result.entry.id} metadata={$metadata}',
      );
      debugPrint('VectorStore: Result ${index + 1} content=$content');
    }
  }
  Future<bool> _hasBundledDbCriticalFootprint(Directory restoreRoot) async {
    for (final relativePath in _bundledDbCriticalRelativePaths) {
      final targetPath = p.normalize(p.join(restoreRoot.path, relativePath));
      if (!await File(targetPath).exists()) {
        return false;
      }
    }
    return true;
  }

  Future<List<String>> _missingBundledFiles(
    Directory restoreRoot,
    List<String> files,
  ) async {
    final missing = <String>[];
    for (final relativePath in files) {
      final targetPath = p.normalize(p.join(restoreRoot.path, relativePath));
      if (!await File(targetPath).exists()) {
        missing.add(relativePath);
      }
    }
    return missing;
  }

  File _bundledDbRestoreMarkerFile(Directory restoreRoot) {
    return File(p.join(restoreRoot.path, _bundledDbRestoreMarkerFileName));
  }

  Future<String> _loadBundledDbRestoreMarkerVersion(Directory restoreRoot) async {
    try {
      final markerFile = _bundledDbRestoreMarkerFile(restoreRoot);
      if (!await markerFile.exists()) {
        return '';
      }
      return (await markerFile.readAsString()).trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _writeBundledDbRestoreMarkerVersion(
    Directory restoreRoot,
    String version,
  ) async {
    final markerFile = _bundledDbRestoreMarkerFile(restoreRoot);
    await markerFile.parent.create(recursive: true);
    await markerFile.writeAsString('$version\n', flush: true);
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
  final String category;
  final String emotion;
  final String translationText;
  final String? arabicText;

  const EmotionalVerse({
    required this.verseKey,
    required this.category,
    required this.emotion,
    required this.translationText,
    this.arabicText,
  });
}

/// Pre-defined emotional verses for seeding the vector store
const kEmotionalVerses = <EmotionalVerse>[
  EmotionalVerse(
    verseKey: '2:286',
    category: 'comfort_relief',
    emotion: 'hardship relief anxiety worry stress overwhelmed burden resilience',
    translationText: 'Allah does not burden a soul beyond that it can bear.',
  ),
  EmotionalVerse(
    verseKey: '94:5',
    category: 'comfort_relief',
    emotion: 'hardship relief sadness difficulty hope ease struggle',
    translationText: 'For indeed, with hardship will be ease.',
  ),
  EmotionalVerse(
    verseKey: '94:6',
    category: 'comfort_relief',
    emotion: 'hardship relief sadness difficulty hope ease struggle',
    translationText: 'Indeed, with hardship will be ease.',
  ),
  EmotionalVerse(
    verseKey: '9:51',
    category: 'comfort_relief',
    emotion: 'hardship decree trust acceptance trial relief surrender',
    translationText: 'Nothing will happen to us except what Allah has decreed for us.',
  ),
  EmotionalVerse(
    verseKey: '94:7-8',
    category: 'comfort_relief',
    emotion: 'hardship worship renewal longing devotion recovery',
    translationText: 'So when you have finished your duties, then stand up for worship. And to your Lord direct your longing.',
  ),
  EmotionalVerse(
    verseKey: '13:28',
    category: 'calm_peace',
    emotion: 'anxiety calm peace heart rest remembrance worry stress',
    translationText: 'Verily, in the remembrance of Allah do hearts find rest.',
  ),
  EmotionalVerse(
    verseKey: '89:27-30',
    category: 'calm_peace',
    emotion: 'peace calm tranquil soul contentment return serenity',
    translationText: 'O tranquil soul, return to your Lord, well-pleased and pleasing.',
  ),
  EmotionalVerse(
    verseKey: '2:152',
    category: 'calm_peace',
    emotion: 'peace remembrance closeness calm heart gratitude',
    translationText: 'So remember Me; I will remember you.',
  ),
  EmotionalVerse(
    verseKey: '39:53',
    category: 'hope_trust',
    emotion: 'hope trust mercy despair guilt regret sin forgiveness',
    translationText: 'O My servants who have transgressed against themselves, do not despair of the mercy of Allah. Indeed, Allah forgives all sins.',
  ),
  EmotionalVerse(
    verseKey: '65:3',
    category: 'hope_trust',
    emotion: 'hope trust reliance uncertainty tawakkul relief provision',
    translationText: 'And whoever relies upon Allah, then He is sufficient for him.',
  ),
  EmotionalVerse(
    verseKey: '12:87',
    category: 'hope_trust',
    emotion: 'hope despair relief hopelessness trust',
    translationText: 'Indeed, no one despairs of relief from Allah except the disbelieving people.',
  ),
  EmotionalVerse(
    verseKey: '7:156',
    category: 'mercy_forgiveness',
    emotion: 'mercy forgiveness compassion hope healing',
    translationText: 'My mercy encompasses all things.',
  ),
  EmotionalVerse(
    verseKey: '4:110',
    category: 'mercy_forgiveness',
    emotion: 'guilt regret forgiveness repentance mercy sin',
    translationText: 'Whoever does a wrong or wrongs himself but then seeks forgiveness of Allah will find Allah Forgiving and Merciful.',
  ),
  EmotionalVerse(
    verseKey: '6:54',
    category: 'mercy_forgiveness',
    emotion: 'mercy compassion hope repentance',
    translationText: 'Your Lord has decreed upon Himself mercy.',
  ),
  EmotionalVerse(
    verseKey: '14:7',
    category: 'gratitude_blessings',
    emotion: 'gratitude thankful blessings increase favor abundance',
    translationText: 'If you are grateful, I will surely increase you.',
  ),
  EmotionalVerse(
    verseKey: '16:18',
    category: 'gratitude_blessings',
    emotion: 'gratitude blessings favors abundance reflection',
    translationText: 'If you tried to count Allah’s favors, you could never enumerate them.',
  ),
  EmotionalVerse(
    verseKey: '2:172',
    category: 'gratitude_blessings',
    emotion: 'gratitude provision blessing thankfulness',
    translationText: 'Eat from the good things We have provided for you and be grateful to Allah.',
  ),
  EmotionalVerse(
    verseKey: '2:153',
    category: 'patience_strength',
    emotion: 'patience strength endurance struggle prayer resilience',
    translationText: 'Indeed, Allah is with the patient.',
  ),
  EmotionalVerse(
    verseKey: '3:139',
    category: 'patience_strength',
    emotion: 'patience strength sadness courage hope grief',
    translationText: 'Do not lose hope nor be sad.',
  ),
  EmotionalVerse(
    verseKey: '29:69',
    category: 'patience_strength',
    emotion: 'patience striving strength guidance perseverance',
    translationText: 'Those who strive for Us, We will surely guide them to Our ways.',
  ),
  EmotionalVerse(
    verseKey: '93:3',
    category: 'hope_trust',
    emotion: 'abandoned forsaken alone lonely reassurance',
    translationText: 'Your Lord has not taken leave of you, nor has He detested you.',
  ),
  EmotionalVerse(
    verseKey: '9:40',
    category: 'calm_peace',
    emotion: 'fear lonely alone calm reassurance',
    translationText: 'Do not grieve; indeed Allah is with us.',
  ),
  EmotionalVerse(
    verseKey: '3:173',
    category: 'hope_trust',
    emotion: 'fear trust safety reliance protection',
    translationText: 'Sufficient for us is Allah, and He is the best Disposer of affairs.',
  ),
];
