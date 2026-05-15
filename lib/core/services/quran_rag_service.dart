import 'package:flutter/foundation.dart';
import '../models/verse.dart';
import 'quran_api_service.dart';
import 'quran_mcp_service.dart';
import '../utils/perf_trace.dart';

typedef QuranSurahVersesLoader = Future<List<Verse>> Function(int surahNumber);
typedef QuranVerseTextLoader = Future<String?> Function(
  int surahNumber,
  int ayahNumber,
);

enum QuranVerseSearchBackend {
  mcp,
  localDb,
  unknown,
}

extension QuranVerseSearchBackendLabel on QuranVerseSearchBackend {
  String get label {
    switch (this) {
      case QuranVerseSearchBackend.mcp:
        return 'MCP';
      case QuranVerseSearchBackend.localDb:
        return 'Local DB';
      case QuranVerseSearchBackend.unknown:
        return 'Unknown';
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
      ? '${backend.label} exact'
      : backend.label;
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

class HadithRagEvidence {
  const HadithRagEvidence({
    required this.reference,
    required this.collection,
    required this.grade,
    required this.content,
  });

  final String reference;
  final String collection;
  final String grade;
  final String content;
}

class QuranRagService {
  QuranRagService({
    QuranSurahVersesLoader? loadSurahVerses,
    QuranVerseTextLoader? loadVerseTafsir,
    QuranVerseTextLoader? loadVerseTafsirSource,
  })  : _loadSurahVerses = loadSurahVerses ?? QuranApiService.instance.getSurahVerses,
        _loadVerseTafsir = loadVerseTafsir ?? QuranApiService.instance.getVerseTafsir,
        _loadVerseTafsirSource =
            loadVerseTafsirSource ?? QuranApiService.instance.getVerseTafsirSource;

  static final QuranRagService instance = QuranRagService();

  static final RegExp _verseKeyPattern = RegExp(r'^(\d{1,3}):(\d{1,3})$');

  final QuranSurahVersesLoader _loadSurahVerses;
  final QuranVerseTextLoader _loadVerseTafsir;
  final QuranVerseTextLoader _loadVerseTafsirSource;

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
    if (match == null) return null;

    final surahNumber = int.parse(match.group(1)!);
    final ayahNumber = int.parse(match.group(2)!);

    // Fetch translation and text via QuranApiService (now uses Content API)
    String translation = '';
    try {
      final verse = await QuranApiService.instance.getVerse(surahNumber, ayahNumber);
      translation = (verse?.translationText ?? '').trim();
    } catch (_) {}

    final tafsir =
        (await _loadVerseTafsir(surahNumber, ayahNumber))?.trim() ?? '';
    final source = await _loadVerseTafsirSource(surahNumber, ayahNumber) ??
        'Quran.com';

    if (translation.isEmpty && tafsir.isEmpty) return null;

    return (
      evidence: QuranRagEvidence(
        verseKey: normalizedVerseKey,
        translationText: translation,
        tafsirText: tafsir,
        tafsirSource: source,
      ),
      backend: QuranVerseSearchBackend.mcp,
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
      if (uniqueKeys.length >= maxItems) break;
      final normalizedVerseKey = verseKey.trim();
      if (normalizedVerseKey.isEmpty || !seenVerseKeys.add(normalizedVerseKey)) continue;
      uniqueKeys.add(normalizedVerseKey);
    }

    final parallel = await Future.wait(
      uniqueKeys.map((key) => retrieveVerseEvidence(key, queryHint: queryHint)),
    );

    return parallel.whereType<QuranRagEvidence>().toList();
  }

  Future<List<QuranRagEvidence>> retrieveGroundedEvidence(
    String rawQuery, {
    int limit = 3,
  }) async {
    final traceTag = PerfTrace.nextTag('rag.retrieveGroundedEvidence');
    final totalSw = PerfTrace.start(traceTag, 'retrieve');
    
    // Use MCP retrieval exclusively (canonical grounding for hackathon)
    try {
      final mcpEvidence = await _retrieveMcpEvidence(rawQuery, limit: limit);
      PerfTrace.end(traceTag, mcpEvidence.isNotEmpty ? 'retrieve_mcp' : 'retrieve_empty', totalSw);
      return mcpEvidence;
    } catch (e) {
      debugPrint('MCP retrieval failed: $e');
      PerfTrace.end(traceTag, 'retrieve_error', totalSw);
      return const [];
    }
  }

  Future<QuranVerseSearchResult> searchVersesDetailed(
    String rawQuery, {
    int limit = 8,
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return const QuranVerseSearchResult.empty();

    // Check exact verse reference first (local DB remains useful for this)
    final exactVerse = await _lookupExactVerseWithSource(query);
    if (exactVerse != null) {
      return QuranVerseSearchResult(
        verses: <Verse>[exactVerse.verse],
        backend: exactVerse.backend,
        isExactVerseMatch: true,
      );
    }

    // Attempt MCP search
    try {
      final mcpEvidence = await _retrieveMcpEvidence(rawQuery, limit: limit);
      if (mcpEvidence.isNotEmpty) {
        final verses = <Verse>[];
        for (final item in mcpEvidence) {
          final parts = item.verseKey.split(':');
          if (parts.length == 2) {
            final sn = int.tryParse(parts[0]);
            final an = int.tryParse(parts[1]);
            if (sn != null && an != null) {
              verses.add(Verse(
                verseKey: item.verseKey,
                surahNumber: sn,
                ayahNumber: an,
                translationText: item.translationText,
              ));
            }
          }
        }
        if (verses.isNotEmpty) {
          return QuranVerseSearchResult(
            verses: verses,
            backend: QuranVerseSearchBackend.mcp,
          );
        }
      }
    } catch (e) {
      debugPrint('MCP search failed: $e');
    }

    return const QuranVerseSearchResult.empty();
  }

  Future<({Verse verse, QuranVerseSearchBackend backend})?>
      _lookupExactVerseWithSource(String query) async {
    final result = await _retrieveVerseEvidenceWithSource(query, queryHint: query);
    if (result == null) return null;

    final match = _verseKeyPattern.firstMatch(result.evidence.verseKey);
    if (match == null) return null;

    return (
      verse: Verse(
        verseKey: result.evidence.verseKey,
        surahNumber: int.parse(match.group(1)!),
        ayahNumber: int.parse(match.group(2)!),
        translationText: result.evidence.translationText,
      ),
      backend: result.backend,
    );
  }

  List<HadithRagEvidence> retrieveHadithEvidence(
    String rawQuery, {
    int limit = 3,
    bool sahihOnly = false,
  }) {
    // Hadith retrieval is currently disabled until a corresponding MCP server is integrated.
    return const [];
  }

  Future<List<QuranRagEvidence>> _retrieveMcpEvidence(String query, {int limit = 3}) async {
    try {
      final results = await QuranMcpService.instance.searchQuran(query);
      final evidence = <QuranRagEvidence>[];
      
      for (final result in results.take(limit)) {
        final verseKey = result['ayah_key'] as String? ?? result['verse_key'] as String?;
        if (verseKey == null) continue;
        
        final parts = verseKey.split(':');
        if (parts.length != 2) continue;
        final sn = int.tryParse(parts[0]) ?? 1;
        final an = int.tryParse(parts[1]) ?? 1;

        // Fetch translation and tafsir via QuranApiService (Content API)
        String translationText = '';
        String tafsirText = '';
        
        try {
          final verse = await QuranApiService.instance.getVerse(sn, an);
          translationText = (verse?.translationText ?? '').trim();
          
          tafsirText = await QuranApiService.instance.getVerseTafsir(sn, an) ?? '';
        } catch (_) {}

        evidence.add(QuranRagEvidence(
          verseKey: verseKey,
          translationText: translationText,
          tafsirText: tafsirText,
          tafsirSource: 'Quran.com',
        ));
      }
      return evidence;
    } catch (e) {
      debugPrint('MCP retrieval error: $e');
      return const [];
    }
  }
}