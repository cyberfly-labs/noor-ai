import '../models/surah.dart';
import '../models/verse.dart';
import 'quran_api_service.dart';
import 'vector_store_service.dart';
import '../utils/perf_trace.dart';

typedef QuranVectorQuery = List<VectorSearchResult> Function(
  String text, {
  int topK,
  bool Function(VectorEntry entry)? filter,
});

typedef QuranDocumentQuery = List<VectorSearchResult> Function(
  String documentId,
  String query, {
  int limit,
});

typedef QuranLexicalSearch = Future<List<Verse>> Function(String query);

typedef QuranSurahVersesLoader = Future<List<Verse>> Function(int surahNumber);

typedef QuranVerseTextLoader = Future<String?> Function(
  int surahNumber,
  int ayahNumber,
);

typedef QuranVectorBackendReader = VectorSearchBackend Function();

enum QuranVerseSearchBackend {
  zvec,
  inMemoryVectors,
  localDb,
  unknown,
}

extension QuranVerseSearchBackendLabel on QuranVerseSearchBackend {
  String get debugLabel {
    switch (this) {
      case QuranVerseSearchBackend.zvec:
        return 'zvec';
      case QuranVerseSearchBackend.inMemoryVectors:
        return 'in-memory';
      case QuranVerseSearchBackend.localDb:
        return 'local DB';
      case QuranVerseSearchBackend.unknown:
        return 'unknown';
    }
  }
}

class QuranVerseSearchResult {
  const QuranVerseSearchResult({
    required this.verses,
    required this.backend,
    this.isExactVerseMatch = false,
  });

  const QuranVerseSearchResult.empty()
      : verses = const <Verse>[],
        backend = QuranVerseSearchBackend.unknown,
        isExactVerseMatch = false;

  final List<Verse> verses;
  final QuranVerseSearchBackend backend;
  final bool isExactVerseMatch;

  String get debugLabel => isExactVerseMatch
      ? '${backend.debugLabel} exact'
      : backend.debugLabel;
}

class QuranRagEvidence {
  const QuranRagEvidence({
    required this.verseKey,
    required this.translationText,
    required this.tafsirText,
    required this.tafsirSource,
  });

  final String verseKey;
  final String translationText;
  final String tafsirText;
  final String tafsirSource;
}

class QuranRagContent {
  const QuranRagContent({
    required this.translationText,
    required this.tafsirText,
  });

  final String translationText;
  final String tafsirText;
}

class HadithRagEvidence {
  const HadithRagEvidence({
    required this.reference,
    required this.collection,
    required this.grade,
    required this.content,
  });

  /// Human-readable citation, e.g. "Sahih al-Bukhari, 1".
  final String reference;

  /// Collection name, e.g. "Sahih al-Bukhari".
  final String collection;

  /// Authenticity grade, e.g. "Sahih".
  final String grade;

  /// Narrator + hadith body (+ grade line) as stored in the vector DB.
  final String content;
}

class _RankedQuranHit {
  const _RankedQuranHit({
    required this.result,
    required this.content,
    required this.score,
  });

  final VectorSearchResult result;
  final QuranRagContent content;
  final double score;
}

class QuranRagService {
  QuranRagService({
    QuranVectorQuery? queryVectors,
    QuranDocumentQuery? searchDocument,
    QuranLexicalSearch? lexicalSearch,
    QuranSurahVersesLoader? loadSurahVerses,
    QuranVerseTextLoader? loadVerseTafsir,
    QuranVerseTextLoader? loadVerseTafsirSource,
    QuranVectorBackendReader? currentVectorBackend,
    QuranVectorBackendReader? currentDocumentBackend,
  })  : _queryVectors = queryVectors ?? VectorStoreService.instance.queryByText,
        _searchDocument = searchDocument ?? VectorStoreService.instance.searchInDocument,
        _lexicalSearch = lexicalSearch ?? QuranApiService.instance.search,
        _loadSurahVerses = loadSurahVerses ?? QuranApiService.instance.getSurahVerses,
        _loadVerseTafsir = loadVerseTafsir ?? QuranApiService.instance.getVerseTafsir,
        _loadVerseTafsirSource =
            loadVerseTafsirSource ?? QuranApiService.instance.getVerseTafsirSource,
        _currentVectorBackend =
            currentVectorBackend ?? (() => VectorStoreService.instance.lastQueryBackend),
        _currentDocumentBackend = currentDocumentBackend ??
            (() => VectorStoreService.instance.lastDocumentQueryBackend);

  static final QuranRagService instance = QuranRagService();

  static final RegExp _verseKeyPattern = RegExp(r'^(\d{1,3}):(\d{1,3})$');
  static final RegExp _nonAlphaNumericPattern = RegExp(r'[^a-z0-9\s:]');
  static final RegExp _multiWhitespacePattern = RegExp(r'\s+');
  static final RegExp _sentenceBoundaryPattern = RegExp(r'(?<=[.!?])\s+');
  static const Set<String> _stopWords = <String>{
    'a',
    'about',
    'all',
    'allah',
    'an',
    'and',
    'answering',
    'be',
    'being',
    'by',
    'does',
    'explain',
    'explanation',
    'for',
    'how',
    'in',
    'is',
    'meaning',
    'near',
    'of',
    'say',
    'tafsir',
    'teach',
    'teaches',
    'the',
    'times',
    'to',
    'toward',
    'what',
  };
  static const Set<String> _queryStructureTerms = <String>{
    'ayah',
    'ayahs',
    'chapter',
    'chapters',
    'quran',
    'sura',
    'surah',
    'surat',
    'suratul',
    'verse',
    'verses',
  };
  static const Map<String, Set<String>> _querySynonyms = <String, Set<String>>{
    'trust': <String>{'relies', 'reliance', 'sufficient', 'tawakkul'},
    'hardship': <String>{'difficulty', 'trial', 'tested', 'affliction'},
    'patience': <String>{'patient', 'persevere', 'perseverance', 'sabr'},
    'prayer': <String>{'supplication', 'dua', 'call', 'salah', 'salat'},
    'repentance': <String>{'repent', 'repented', 'tawbah', 'return'},
    'mercy': <String>{'merciful', 'forgiving', 'forgiveness', 'pardon', 'compassion'},
    'sinners': <String>{'sins', 'sin', 'wrongdoing', 'transgressed', 'transgression'},
    'guidance': <String>{'guide', 'guided', 'straight', 'path', 'rightly'},
    'forgiveness': <String>{'forgiving', 'forgive', 'mercy', 'merciful', 'pardon'},
    'supplication': <String>{'dua', 'call', 'invocation', 'prayer'},
    'hell': <String>{'hellfire', 'jahannam', 'fire', 'punishment', 'torment', 'blazing'},
    'paradise': <String>{'jannah', 'heaven', 'garden', 'gardens', 'reward', 'bliss'},
    'kill': <String>{'slay', 'slain', 'killing', 'murder', 'slaughter'},
    'war': <String>{'fight', 'fighting', 'battle', 'strive', 'combat', 'jihad'},
    'death': <String>{'die', 'dead', 'perish', 'dying', 'grave', 'hereafter'},
    'worship': <String>{'prostrate', 'prostration', 'devotion', 'serve', 'ibadah'},
    'fasting': <String>{'fast', 'sawm', 'abstain'},
    'charity': <String>{'zakat', 'sadaqah', 'alms', 'spending', 'generous'},
    'angel': <String>{'angels', 'malaika', 'gabriel', 'jibreel'},
    'devil': <String>{'shaytan', 'satan', 'iblis', 'whisper'},
    'prophet': <String>{'messenger', 'messengers', 'prophets', 'rasul', 'nabi'},
    'judgment': <String>{'qiyamah', 'resurrection', 'reckoning', 'accounting'},
    'justice': <String>{'equity', 'fair', 'oppression', 'oppressor', 'tyranny'},
    'wealth': <String>{'provision', 'rizq', 'rich', 'poor', 'poverty'},
    'knowledge': <String>{'wisdom', 'wise', 'learn', 'understanding', 'ilm'},
    'disbelief': <String>{'disbelievers', 'kafir', 'reject', 'denial', 'deny'},
    'faith': <String>{'believers', 'iman', 'righteous', 'pious', 'believe'},
    'creation': <String>{'created', 'creator', 'heavens', 'earth'},
    'soul': <String>{'nafs', 'spirit', 'self', 'heart'},
    'fear': <String>{'taqwa', 'piety', 'conscious', 'awe', 'afraid'},
    'light': <String>{'nur', 'darkness', 'illuminate', 'blind'},
    'covenant': <String>{'promise', 'pledge', 'oath', 'treaty'},
    'obedience': <String>{'obey', 'obedient', 'disobey', 'rebel'},
    'grateful': <String>{'gratitude', 'thankful', 'shukr', 'ungrateful'},
    'truth': <String>{'truthful', 'honest', 'falsehood', 'liar'},
    'family': <String>{'children', 'offspring', 'parents', 'mother', 'father'},
    'water': <String>{'rain', 'rivers', 'sea', 'ocean', 'flood'},
    'marriage': <String>{'spouse', 'husband', 'wife', 'marry'},
    // Named verse expansions
    'kursi': <String>{'throne', 'sovereignty', 'footstool', 'heavens', 'earth', 'eternal', 'living', 'sustainer'},
    'ayatul': <String>{'verse', 'ayah', 'throne', 'kursi'},
    'throne': <String>{'kursi', 'sovereignty', 'eternal', 'living', 'footstool'},
    'noor': <String>{'light', 'nur', 'illuminate', 'guidance'},
    'fatiha': <String>{'opening', 'praise', 'lord', 'guide', 'path', 'worship'},
    'ikhlas': <String>{'sincerity', 'oneness', 'ahad', 'samad', 'eternal'},
    'falaq': <String>{'daybreak', 'refuge', 'evil', 'darkness'},
    'nas': <String>{'mankind', 'people', 'whisper', 'jinn', 'refuge'},
    'yaseen': <String>{'yasin', 'heart', 'quran', 'soul', 'resurrection'},
    'mulk': <String>{'dominion', 'sovereignty', 'death', 'life', 'creation'},
    'rahman': <String>{'merciful', 'blessings', 'creation', 'grace'},
    'waqiah': <String>{'event', 'resurrection', 'three groups', 'companions'},
  };

  static final Map<String, Set<String>> _reverseSynonymIndex =
      _buildReverseSynonymIndex();

  static Map<String, Set<String>> _buildReverseSynonymIndex() {
    final index = <String, Set<String>>{};
    for (final entry in _querySynonyms.entries) {
      for (final synonym in entry.value) {
        final related = (index[synonym] ??= <String>{});
        related.add(entry.key);
        related.addAll(entry.value);
        related.remove(synonym);
      }
    }
    return index;
  }

  final QuranVectorQuery _queryVectors;
  final QuranDocumentQuery _searchDocument;
  final QuranLexicalSearch _lexicalSearch;
  final QuranSurahVersesLoader _loadSurahVerses;
  final QuranVerseTextLoader _loadVerseTafsir;
  final QuranVerseTextLoader _loadVerseTafsirSource;
  final QuranVectorBackendReader _currentVectorBackend;
  final QuranVectorBackendReader _currentDocumentBackend;
  final Map<String, List<_RankedQuranHit>> _rankedHitsCache =
      <String, List<_RankedQuranHit>>{};
  final Map<String, QuranRagContent> _entryContentCache =
      <String, QuranRagContent>{};
  final Map<String, Set<String>> _tokenCache = <String, Set<String>>{};
  static const int _maxRankedHitsCacheEntries = 80;
  static const int _maxTextCacheEntries = 240;

  Future<QuranRagEvidence?> retrieveVerseEvidence(
    String verseKey, {
    String? queryHint,
  }) async {
    final result = await _retrieveVerseEvidenceWithSource(
      verseKey,
      queryHint: queryHint,
    );
    return result?.evidence;
  }

  Future<({QuranRagEvidence evidence, QuranVerseSearchBackend backend})?>
      _retrieveVerseEvidenceWithSource(
    String verseKey, {
    String? queryHint,
  }) async {
    final normalizedVerseKey = verseKey.trim();
    final match = _verseKeyPattern.firstMatch(normalizedVerseKey);
    if (match == null) {
      return null;
    }

    final logicalHash = 'quran_$normalizedVerseKey';
    final query = normalizeQuery(queryHint?.trim().isNotEmpty == true
        ? queryHint!
        : 'meaning tafsir translation verse $normalizedVerseKey');
    final results = _searchDocument(logicalHash, query, limit: 1);
    if (results.isNotEmpty) {
      final result = results.first;
      final content = parseEntryContent(result.entry.content);
      if (content.translationText.isNotEmpty || content.tafsirText.isNotEmpty) {
        return (
          evidence: QuranRagEvidence(
            verseKey: normalizedVerseKey,
            translationText: content.translationText,
            tafsirText: content.tafsirText,
            tafsirSource: result.entry.metadata['source'] ?? 'Local English Tafsir',
          ),
          backend: _mapVectorBackend(_currentDocumentBackend()),
        );
      }
    }

    // Fallback 1: some prebuilt/native DB layouts can miss searchInDocument by
    // logical hash. Query globally but force exact verse_key metadata match.
    final exactVerseHits = _queryVectors(
      query,
      topK: 8,
      filter: (entry) =>
          _isQuranCorpusEntry(entry) &&
          entry.metadata['verse_key'] == normalizedVerseKey,
    );
    if (exactVerseHits.isNotEmpty) {
      final best = exactVerseHits.first;
      final content = parseEntryContent(best.entry.content);
      if (content.translationText.isNotEmpty || content.tafsirText.isNotEmpty) {
        return (
          evidence: QuranRagEvidence(
            verseKey: normalizedVerseKey,
            translationText: content.translationText,
            tafsirText: content.tafsirText,
            tafsirSource: best.entry.metadata['source'] ?? 'Local English Tafsir',
          ),
          backend: _mapVectorBackend(_currentVectorBackend()),
        );
      }
    }

    // Fallback 2: load directly from local Quran assets through API service.
    final surahNumber = int.parse(match.group(1)!);
    final ayahNumber = int.parse(match.group(2)!);
    final surahVerses = await _loadSurahVerses(surahNumber);
    Verse? verse;
    for (final item in surahVerses) {
      if (item.ayahNumber == ayahNumber) {
        verse = item;
        break;
      }
    }
    if (verse == null) {
      return null;
    }

    final translation = (verse.translationText ?? '').trim();
    final tafsir =
        (await _loadVerseTafsir(surahNumber, ayahNumber))?.trim() ?? '';
    final source =
        await _loadVerseTafsirSource(surahNumber, ayahNumber) ??
            'Local English Tafsir';
    if (translation.isEmpty && tafsir.isEmpty) {
      return null;
    }

    return (
      evidence: QuranRagEvidence(
        verseKey: normalizedVerseKey,
        translationText: translation,
        tafsirText: tafsir,
        tafsirSource: source,
      ),
      backend: QuranVerseSearchBackend.localDb,
    );
  }

  Future<List<QuranRagEvidence>> retrieveVerseEvidenceBatch(
    List<String> verseKeys, {
    int maxItems = 3,
    String? queryHint,
  }) async {
    final seenVerseKeys = <String>{};
    final uniqueKeys = <String>[];
    for (final verseKey in verseKeys) {
      if (uniqueKeys.length >= maxItems) {
        break;
      }

      final normalizedVerseKey = verseKey.trim();
      if (normalizedVerseKey.isEmpty || !seenVerseKeys.add(normalizedVerseKey)) {
        continue;
      }

      uniqueKeys.add(normalizedVerseKey);
    }

    final parallel = await Future.wait(
      uniqueKeys.map(
        (key) => retrieveVerseEvidence(key, queryHint: queryHint),
      ),
    );

    final evidence = <QuranRagEvidence>[];
    for (final item in parallel) {
      if (item != null) {
        evidence.add(item);
      }
    }
    return evidence;
  }

  Future<List<QuranRagEvidence>> retrieveGroundedEvidence(
    String rawQuery, {
    int limit = 3,
  }) async {
    final traceTag = PerfTrace.nextTag('rag.retrieveGroundedEvidence');
    final totalSw = PerfTrace.start(traceTag, 'retrieve');
    final normalizedQuery = normalizeQuery(rawQuery);
    if (normalizedQuery.isEmpty) {
      PerfTrace.end(traceTag, 'retrieve_empty', totalSw);
      return const <QuranRagEvidence>[];
    }

    final rankedSw = Stopwatch()..start();
    final rankedHits = _retrieveRankedHits(rawQuery, limit: limit);
    PerfTrace.mark(traceTag, 'ranked_hits', rankedSw);

    final evidence = <QuranRagEvidence>[];
    final seenVerseKeys = <String>{};

    for (final hit in rankedHits) {
      final result = hit.result;
      final verseKey = result.entry.metadata['verse_key'] ?? '';
      if (verseKey.isEmpty || !seenVerseKeys.add(verseKey)) {
        continue;
      }

      final content = hit.content;
      if (content.translationText.isEmpty) {
        continue;
      }

      evidence.add(QuranRagEvidence(
        verseKey: verseKey,
        translationText: content.translationText,
        tafsirText: content.tafsirText,
        tafsirSource: result.entry.metadata['source'] ?? 'Local English Tafsir',
      ));

      if (evidence.length >= limit) {
        break;
      }
    }

    if (evidence.length < limit) {
      final fallbackSw = Stopwatch()..start();
      final fallbackEvidence = await _retrieveLexicalFallbackEvidence(
        rawQuery,
        limit: limit - evidence.length,
        excludeVerseKeys: seenVerseKeys,
      );
      PerfTrace.mark(traceTag, 'lexical_fallback', fallbackSw);
      evidence.addAll(fallbackEvidence);
    }

    PerfTrace.end(traceTag, 'retrieve', totalSw);
    return evidence;
  }

  Future<List<Verse>> searchVerses(
    String rawQuery, {
    int limit = 8,
  }) async {
    final result = await searchVersesDetailed(rawQuery, limit: limit);
    return result.verses;
  }

  Future<QuranVerseSearchResult> searchVersesDetailed(
    String rawQuery, {
    int limit = 8,
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return const QuranVerseSearchResult.empty();
    }

    final exactVerse = await _lookupExactVerseWithSource(query);
    if (exactVerse != null) {
      return QuranVerseSearchResult(
        verses: <Verse>[exactVerse.verse],
        backend: exactVerse.backend,
        isExactVerseMatch: true,
      );
    }

    final rankedHits = _retrieveRankedHits(rawQuery, limit: limit);

    return QuranVerseSearchResult(
      verses: await _hydrateVerses(
        rankedHits.map((hit) => hit.result).toList(growable: false),
        limit: limit,
      ),
      backend: _mapVectorBackend(_currentVectorBackend()),
    );
  }

  String normalizeQuery(String input) {
    final normalized = input
        .toLowerCase()
        .replaceAll(_nonAlphaNumericPattern, ' ')
        .replaceAll(_multiWhitespacePattern, ' ')
        .trim();
    return normalized;
  }

  QuranRagContent parseEntryContent(String content) {
    final cacheKey = content;
    final cached = _entryContentCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    const translationPrefix = 'Translation: ';
    const tafsirPrefix = 'Tafsir: ';

    final lines = content.split(RegExp(r'\r?\n'));
    String translationText = '';
    final tafsirLines = <String>[];

    for (final line in lines) {
      if (line.startsWith(translationPrefix)) {
        translationText = line.substring(translationPrefix.length).trim();
        continue;
      }
      if (line.startsWith(tafsirPrefix)) {
        final firstLine = line.substring(tafsirPrefix.length).trim();
        if (firstLine.isNotEmpty) {
          tafsirLines.add(firstLine);
        }
        continue;
      }
      if (tafsirLines.isNotEmpty && line.trim().isNotEmpty) {
        tafsirLines.add(line.trim());
      }
    }

    final parsed = QuranRagContent(
      translationText: translationText,
      tafsirText: tafsirLines.join(' ').trim(),
    );
    _putCacheEntry(_entryContentCache, cacheKey, parsed, _maxTextCacheEntries);
    return parsed;
  }

  List<_RankedQuranHit> _retrieveRankedHits(
    String rawQuery, {
    required int limit,
  }) {
    final normalizedQuery = normalizeQuery(rawQuery);
    if (normalizedQuery.isEmpty) {
      return const <_RankedQuranHit>[];
    }

    final queryTerms = _buildQueryTerms(rawQuery);
    final embeddingQuery = _augmentQueryForEmbedding(normalizedQuery, queryTerms);
    final wordCount = normalizedQuery.split(' ').where((w) => w.isNotEmpty).length;
    final topK = wordCount <= 2 ? 20 : (limit <= 3 ? 12 : limit * 4);
    final cacheKey = '$embeddingQuery|$topK';
    final cachedHits = _rankedHitsCache[cacheKey];
    if (cachedHits != null) {
      return cachedHits;
    }

    final results = _queryVectors(
      embeddingQuery,
      topK: topK,
      filter: _isQuranCorpusEntry,
    );

    final rankedHits = <_RankedQuranHit>[];
    for (final result in results) {
      final parsed = parseEntryContent(result.entry.content);
      if (parsed.translationText.isEmpty && parsed.tafsirText.isEmpty) {
        continue;
      }

      final focusedTafsir = _extractRelevantTafsirSnippet(
        parsed.tafsirText,
        queryTerms,
      );
      final content = QuranRagContent(
        translationText: parsed.translationText,
        tafsirText: focusedTafsir.isEmpty ? parsed.tafsirText : focusedTafsir,
      );
      rankedHits.add(_RankedQuranHit(
        result: result,
        content: content,
        score: _scoreHit(result, content, queryTerms),
      ));
    }

    rankedHits.sort((a, b) => b.score.compareTo(a.score));
    _putCacheEntry(
      _rankedHitsCache,
      cacheKey,
      List<_RankedQuranHit>.unmodifiable(rankedHits),
      _maxRankedHitsCacheEntries,
    );
    return rankedHits;
  }

  Set<String> _buildQueryTerms(String rawQuery) {
    final normalized = normalizeQuery(rawQuery);
    final allCandidates = normalized
        .split(' ')
        .map((term) => term.trim())
        .where((term) =>
            term.length >= 3 &&
            !_stopWords.contains(term) &&
            !_queryStructureTerms.contains(term))
        .toSet();
    final baseTerms = allCandidates
        .where((term) => SurahLookup.findExactSurahNumber(term) == null)
        .toSet();
    // If every candidate was filtered as a surah name (e.g. "cave"),
    // keep them as content terms — the user is likely asking about the topic.
    final effectiveTerms = baseTerms.isNotEmpty ? baseTerms : allCandidates;
    final expandedTerms = <String>{...effectiveTerms};
    for (final term in effectiveTerms) {
      expandedTerms.addAll(_querySynonyms[term] ?? const <String>{});
      expandedTerms.addAll(_reverseSynonymIndex[term] ?? const <String>{});
    }
    return expandedTerms;
  }

  /// For short queries (≤3 words), appends synonym-expanded terms to the
  /// embedding input so the vector search sees richer context.
  String _augmentQueryForEmbedding(
    String normalizedQuery,
    Set<String> queryTerms,
  ) {
    final words = normalizedQuery.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length > 3 || queryTerms.isEmpty) {
      return normalizedQuery;
    }
    final augmented = <String>[...words];
    for (final term in queryTerms) {
      if (!augmented.contains(term)) {
        augmented.add(term);
      }
      if (augmented.length >= 8) break;
    }
    return augmented.join(' ');
  }

  Future<List<QuranRagEvidence>> _retrieveLexicalFallbackEvidence(
    String rawQuery, {
    required int limit,
    required Set<String> excludeVerseKeys,
  }) async {
    if (limit <= 0) {
      return const <QuranRagEvidence>[];
    }

    final surahNumber = SurahLookup.findSurahNumber(rawQuery);
    final queryTerms = _buildQueryTerms(rawQuery);
    if (queryTerms.isEmpty) {
      return const <QuranRagEvidence>[];
    }

    if (surahNumber != null) {
      final scopedEvidence = await _retrieveSurahScopedEvidence(
        surahNumber,
        queryTerms,
        limit: limit,
        excludeVerseKeys: excludeVerseKeys,
      );
      if (scopedEvidence.isNotEmpty) {
        return scopedEvidence;
      }
    }

    return _retrieveGlobalLexicalEvidence(
      queryTerms,
      limit: limit,
      excludeVerseKeys: excludeVerseKeys,
    );
  }

  Future<List<QuranRagEvidence>> _retrieveSurahScopedEvidence(
    int surahNumber,
    Set<String> queryTerms, {
    required int limit,
    required Set<String> excludeVerseKeys,
  }) async {
    final verses = await _loadSurahVerses(surahNumber);
    if (verses.isEmpty) {
      return const <QuranRagEvidence>[];
    }

    final preRankedVerses = <({Verse verse, int score})>[];
    for (final verse in verses) {
      if (excludeVerseKeys.contains(verse.verseKey)) {
        continue;
      }

      final translationText = verse.translationText?.trim() ?? '';
      if (translationText.isEmpty) {
        continue;
      }

      final translationMatches =
          queryTerms.intersection(_tokenizeContent(translationText)).length;
      if (translationMatches == 0) {
        continue;
      }

      preRankedVerses.add((verse: verse, score: translationMatches));
    }

    preRankedVerses.sort((a, b) => b.score.compareTo(a.score));
    final candidateVerses = preRankedVerses
        .take((limit * 8).clamp(8, 36))
        .map((entry) => entry.verse)
        .toList(growable: false);

    final candidateEvidence = await Future.wait(
      candidateVerses.map((verse) => _lexicalEvidenceForVerse(verse, queryTerms)),
    );

    final scoredEvidence = <({QuranRagEvidence evidence, double score})>[];
    for (final candidate in candidateEvidence) {
      if (candidate == null) {
        continue;
      }

      scoredEvidence.add(candidate);
    }

    scoredEvidence.sort((a, b) => b.score.compareTo(a.score));
    return scoredEvidence
        .take(limit)
        .map((item) => item.evidence)
        .toList(growable: false);
  }

  Future<List<QuranRagEvidence>> _retrieveGlobalLexicalEvidence(
    Set<String> queryTerms, {
    required int limit,
    required Set<String> excludeVerseKeys,
  }) async {
    final rankedVerses = <String, ({Verse verse, double score})>{};
    final termList = queryTerms.toList(growable: false);

    final lexicalResults = await Future.wait(
      termList.take(6).map((term) => _lexicalSearch(term)),
    );

    for (final verses in lexicalResults) {
      for (var index = 0; index < verses.length; index += 1) {
        final verse = verses[index];
        if (excludeVerseKeys.contains(verse.verseKey)) {
          continue;
        }

        final rankScore = 1.0 / (index + 1);
        final existing = rankedVerses[verse.verseKey];
        if (existing == null || rankScore > existing.score) {
          rankedVerses[verse.verseKey] = (verse: verse, score: rankScore);
        }
      }
    }

    final topCandidates = rankedVerses.values
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));
    final narrowedCandidates = topCandidates
        .take((limit * 10).clamp(10, 50))
        .toList(growable: false);
    final lexicalEvidence = await Future.wait(
      narrowedCandidates
          .map((candidate) => _lexicalEvidenceForVerse(candidate.verse, queryTerms)),
    );

    final scoredEvidence = <({QuranRagEvidence evidence, double score})>[];
    for (var i = 0; i < narrowedCandidates.length; i += 1) {
      final evidence = lexicalEvidence[i];
      if (evidence == null) {
        continue;
      }

      scoredEvidence.add((
        evidence: evidence.evidence,
        score: evidence.score + narrowedCandidates[i].score,
      ));
    }

    scoredEvidence.sort((a, b) => b.score.compareTo(a.score));
    return scoredEvidence
        .take(limit)
        .map((item) => item.evidence)
        .toList(growable: false);
  }

  Future<({QuranRagEvidence evidence, double score})?> _lexicalEvidenceForVerse(
    Verse verse,
    Set<String> queryTerms,
  ) async {
    final translationText = verse.translationText?.trim() ?? '';
    if (translationText.isEmpty) {
      return null;
    }
    final tafsirText = (await _loadVerseTafsir(verse.surahNumber, verse.ayahNumber))?.trim() ?? '';

    final translationTerms = _tokenizeContent(translationText);
    final tafsirTerms = _tokenizeContent(tafsirText);
    final translationMatches = queryTerms.intersection(translationTerms).length;
    final tafsirMatches = queryTerms.intersection(tafsirTerms).length;
    final matchCount = translationMatches + tafsirMatches;
    if (matchCount == 0) {
      return null;
    }

    final focusedTafsir = _extractRelevantTafsirSnippet(tafsirText, queryTerms);
    final source = await _loadVerseTafsirSource(verse.surahNumber, verse.ayahNumber) ??
        'Local English Tafsir';
    final score = matchCount / queryTerms.length;
    return (
      evidence: QuranRagEvidence(
        verseKey: verse.verseKey,
        translationText: translationText,
        tafsirText: focusedTafsir.isEmpty ? tafsirText : focusedTafsir,
        tafsirSource: source,
      ),
      score: score,
    );
  }

  double _scoreHit(
    VectorSearchResult result,
    QuranRagContent content,
    Set<String> queryTerms,
  ) {
    if (queryTerms.isEmpty) {
      return result.score;
    }

    final translationTerms = _tokenizeContent(content.translationText);
    final tafsirTerms = _tokenizeContent(content.tafsirText);
    final translationMatches = queryTerms.intersection(translationTerms).length;
    final tafsirMatches = queryTerms.intersection(tafsirTerms).length;
    final matchCoverage = (translationMatches + tafsirMatches) / queryTerms.length;
    final translationBonus = translationMatches / queryTerms.length;
    final tafsirBonus = tafsirMatches / queryTerms.length;
    return (result.score * 0.55) +
      (matchCoverage * 0.20) +
      (translationBonus * 0.10) +
      (tafsirBonus * 0.15);
  }

  Set<String> _tokenizeContent(String text) {
    final cacheKey = text;
    final cached = _tokenCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final tokenized = normalizeQuery(text)
        .split(' ')
        .map((token) => token.trim())
        .where((token) => token.length >= 3)
        .toSet();
    _putCacheEntry(_tokenCache, cacheKey, tokenized, _maxTextCacheEntries);
    return tokenized;
  }

  String _extractRelevantTafsirSnippet(String tafsirText, Set<String> queryTerms) {
    final normalizedTafsir = tafsirText.trim();
    if (normalizedTafsir.isEmpty) {
      return '';
    }

    final sentences = normalizedTafsir
        .split(_sentenceBoundaryPattern)
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);
    if (sentences.length <= 2 || queryTerms.isEmpty) {
      return sentences.take(2).join(' ').trim();
    }

    final rankedSentences = sentences.map((sentence) {
      final sentenceTerms = _tokenizeContent(sentence);
      final overlap = queryTerms.intersection(sentenceTerms).length;
      return (sentence: sentence, score: overlap.toDouble());
    }).toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    final bestSentences = rankedSentences
        .where((entry) => entry.score > 0)
        .take(2)
        .map((entry) => entry.sentence)
        .toList(growable: false);

    if (bestSentences.isEmpty) {
      return sentences.take(2).join(' ').trim();
    }

    return bestSentences.join(' ').trim();
  }

  bool _isQuranCorpusEntry(VectorEntry entry) =>
      entry.metadata['kind'] == 'quran_corpus';

  bool _isHadithCorpusEntry(VectorEntry entry) =>
      entry.metadata['kind'] == 'hadith_corpus';

  QuranVerseSearchBackend _mapVectorBackend(VectorSearchBackend backend) {
    switch (backend) {
      case VectorSearchBackend.nativeZvec:
        return QuranVerseSearchBackend.zvec;
      case VectorSearchBackend.inMemory:
        return QuranVerseSearchBackend.inMemoryVectors;
      case VectorSearchBackend.unknown:
        return QuranVerseSearchBackend.unknown;
    }
  }

  static bool _isSahihGrade(String grade) {
    final lower = grade.toLowerCase();
    return lower.contains('sahih') || lower.contains('hasan');
  }

  /// Return up to [limit] hadith evidence blocks semantically relevant to [rawQuery].
  ///
  /// All grades are returned by default. Pass [sahihOnly]=true to restrict to
  /// Sahih/Hasan grades only. Returns an empty list when no hadith documents are
  /// present in the vector store (e.g. before the hadith corpus has been ingested).
  List<HadithRagEvidence> retrieveHadithEvidence(
    String rawQuery, {
    int limit = 3,
    bool sahihOnly = false,
  }) {
    final normalizedQuery = normalizeQuery(rawQuery);
    if (normalizedQuery.isEmpty) return const <HadithRagEvidence>[];

    final queryTerms = _buildQueryTerms(rawQuery);
    final embeddingQuery = _augmentQueryForEmbedding(normalizedQuery, queryTerms);
    final results = _queryVectors(
      embeddingQuery,
      topK: limit * 6,  // fetch extra to have enough after grade filtering
      filter: _isHadithCorpusEntry,
    );

    final evidence = <HadithRagEvidence>[];
    final seenUrns = <String>{};
    for (final result in results) {
      final meta = result.entry.metadata;
      final urn = meta['urn'] ?? '';
      if (urn.isEmpty || !seenUrns.add(urn)) continue;

      final grade = meta['grade'] ?? '';
      if (sahihOnly && !_isSahihGrade(grade)) continue;

      final content = result.entry.content.trim();
      if (content.isEmpty) continue;

      evidence.add(HadithRagEvidence(
        reference: meta['reference'] ?? meta['collection'] ?? 'Hadith',
        collection: meta['collection'] ?? '',
        grade: grade,
        content: content,
      ));

      if (evidence.length >= limit) break;
    }
    return evidence;
  }

  Future<({Verse verse, QuranVerseSearchBackend backend})?>
      _lookupExactVerseWithSource(String query) async {
    final result = await _retrieveVerseEvidenceWithSource(query, queryHint: query);
    if (result == null) {
      return null;
    }
    final match = _verseKeyPattern.firstMatch(result.evidence.verseKey);
    if (match == null) {
      return null;
    }

    final surahNumber = int.parse(match.group(1)!);
    final ayahNumber = int.parse(match.group(2)!);
    return (
      verse: Verse(
        verseKey: result.evidence.verseKey,
        surahNumber: surahNumber,
        ayahNumber: ayahNumber,
        translationText: result.evidence.translationText,
      ),
      backend: result.backend,
    );
  }

  Future<List<Verse>> _hydrateVerses(
    List<VectorSearchResult> results, {
    required int limit,
  }) async {
    final verses = <Verse>[];
    final seenVerseKeys = <String>{};

    for (final result in results) {
      final verseKey = result.entry.metadata['verse_key'] ?? '';
      if (verseKey.isEmpty || !seenVerseKeys.add(verseKey)) {
        continue;
      }

      final match = _verseKeyPattern.firstMatch(verseKey);
      if (match == null) {
        continue;
      }

      final surahNumber = int.parse(match.group(1)!);
      final ayahNumber = int.parse(match.group(2)!);
      final parsed = parseEntryContent(result.entry.content);
      verses.add(Verse(
        verseKey: verseKey,
        surahNumber: surahNumber,
        ayahNumber: ayahNumber,
        translationText: parsed.translationText.isNotEmpty
            ? parsed.translationText
            : result.entry.content.trim(),
      ));

      if (verses.length >= limit) {
        break;
      }
    }

    return verses;
  }

  void _putCacheEntry<T>(
    Map<String, T> cache,
    String key,
    T value,
    int maxEntries,
  ) {
    if (cache.length >= maxEntries) {
      final oldestKey = cache.keys.first;
      cache.remove(oldestKey);
    }
    cache[key] = value;
  }
}