import 'package:flutter_test/flutter_test.dart';
import 'package:noor_ai/core/models/verse.dart';
import 'package:noor_ai/core/services/quran_rag_service.dart';
import 'package:noor_ai/core/services/vector_store_service.dart';

void main() {
  group('QuranRagService', () {
    test('retrieveGroundedEvidence parses vector content and dedupes verse keys', () async {
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) {
          final results = <VectorSearchResult>[
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_39:53_a',
                content: 'Verse 39:53\nTranslation: O My servants who have transgressed\nTafsir: Allah calls sinners back to mercy.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '39:53',
                  'source': 'Test Tafsir',
                },
              ),
              score: 0.91,
            ),
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_39:53_b',
                content: 'Verse 39:53\nTranslation: Duplicate\nTafsir: Duplicate',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '39:53',
                },
              ),
              score: 0.89,
            ),
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_40:60',
                content: 'Verse 40:60\nTranslation: Call upon Me\nTafsir: Allah promises a response to sincere dua.\nAnd warns against arrogance.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '40:60',
                },
              ),
              score: 0.86,
            ),
          ];
          return filter == null
              ? results
              : results.where((item) => filter(item.entry)).toList(growable: false);
        },
        lexicalSearch: (_) async => const <Verse>[],
      );

      final evidence = await service.retrieveGroundedEvidence('mercy and dua', limit: 3);

      expect(evidence, hasLength(2));
      expect(evidence.first.verseKey, '39:53');
      expect(evidence.first.translationText, 'O My servants who have transgressed');
      expect(evidence.first.tafsirText, 'Allah calls sinners back to mercy.');
      expect(evidence.first.tafsirSource, 'Test Tafsir');
      expect(evidence.last.verseKey, '40:60');
      expect(
        evidence.last.tafsirText,
        'Allah promises a response to sincere dua. And warns against arrogance.',
      );
    });

    test('searchVerses hydrates verses from quran corpus vector hits in rank order', () async {
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) {
          final results = <VectorSearchResult>[
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_94:5',
                content: 'Verse 94:5\nTranslation: With hardship comes ease\nTafsir: Relief follows difficulty.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '94:5',
                },
              ),
              score: 0.95,
            ),
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_94:6',
                content: 'Verse 94:6\nTranslation: Indeed with hardship comes ease\nTafsir: Repetition reinforces hope.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '94:6',
                },
              ),
              score: 0.93,
            ),
          ];
          return filter == null
              ? results
              : results.where((item) => filter(item.entry)).toList(growable: false);
        },
      );

      final verses = await service.searchVerses('hardship and ease', limit: 2);

      expect(verses.map((item) => item.verseKey).toList(), <String>['94:5', '94:6']);
      expect(verses.first.translationText, 'With hardship comes ease');
    });

    test('searchVerses bypasses vector retrieval for exact verse key queries', () async {
      var queryCount = 0;
      var searchDocumentCalls = 0;
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) {
          queryCount += 1;
          return const <VectorSearchResult>[];
        },
        searchDocument: (
          String documentId,
          String query, {
          int limit = 1,
        }) {
          searchDocumentCalls += 1;
          return <VectorSearchResult>[
            VectorSearchResult(
              entry: VectorEntry(
                id: 'chunk_quran_2_255_0',
                content: 'Translation: Ayat al-Kursi\nTafsir: Allah alone deserves worship.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '2:255',
                },
              ),
              score: 1.0,
            ),
          ];
        },
      );

      final verses = await service.searchVerses('2:255');

      expect(queryCount, 0);
      expect(searchDocumentCalls, 1);
      expect(verses, hasLength(1));
      expect(verses.single.verseKey, '2:255');
      expect(verses.single.translationText, 'Ayat al-Kursi');
    });

    test('retrieveVerseEvidence uses exact document search', () async {
      var searchDocumentCalls = 0;
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) => const <VectorSearchResult>[],
        searchDocument: (
          String documentId,
          String query, {
          int limit = 1,
        }) {
          searchDocumentCalls += 1;
          expect(documentId, 'quran_2:255');
          return <VectorSearchResult>[
            VectorSearchResult(
              entry: VectorEntry(
                id: 'chunk_quran_2_255_0',
                content: 'Translation: Allah - there is no deity except Him.\nTafsir: This verse affirms Allahs perfect life, knowledge, and sovereignty.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '2:255',
                  'source': 'Local English Tafsir',
                },
              ),
              score: 1.0,
            ),
          ];
        },
      );

      final evidence = await service.retrieveVerseEvidence('2:255');

      expect(searchDocumentCalls, 1);
      expect(evidence, isNotNull);
      expect(evidence!.verseKey, '2:255');
      expect(evidence.translationText, contains('there is no deity'));
      expect(evidence.tafsirText, contains('perfect life'));
    });

    test('retrieveGroundedEvidence reranks hits using lexical overlap', () async {
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) {
          final results = <VectorSearchResult>[
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_1',
                content: 'Translation: General reminder\nTafsir: This verse discusses obedience in broad terms.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '5:11',
                },
              ),
              score: 0.92,
            ),
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_2',
                content: 'Translation: Whoever relies upon Allah, He is sufficient for him.\nTafsir: Those who trust Allah and rely on Him will find Him enough in hardship and trial.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '65:3',
                },
              ),
              score: 0.75,
            ),
          ];
          return filter == null
              ? results
              : results.where((item) => filter(item.entry)).toList(growable: false);
        },
      );

      final evidence = await service.retrieveGroundedEvidence(
        'trust Allah in hardship',
        limit: 1,
      );

      expect(evidence, hasLength(1));
      expect(evidence.single.verseKey, '65:3');
    });

    test('retrieveGroundedEvidence extracts the most relevant tafsir snippet', () async {
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) {
          final results = <VectorSearchResult>[
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_2_186',
                content: 'Translation: I am near.\nTafsir: This verse states that Allah is close to His servants. The verse explains that He answers dua and hears the supplication of the caller. Believers are commanded to respond with faith and obedience.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '2:186',
                },
              ),
              score: 0.80,
            ),
          ];
          return results;
        },
      );

      final evidence = await service.retrieveGroundedEvidence(
        'answering dua near',
        limit: 1,
      );

      expect(evidence, hasLength(1));
      expect(evidence.single.tafsirText, contains('answers dua'));
      expect(evidence.single.tafsirText, isNot(contains('Believers are commanded')));
    });

    test('retrieveGroundedEvidence falls back to surah scoped lexical evidence', () async {
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) => const <VectorSearchResult>[],
        loadSurahVerses: (int surahNumber) async {
          expect(surahNumber, 5);
          return const <Verse>[
            Verse(
              verseKey: '5:10',
              surahNumber: 5,
              ayahNumber: 10,
              translationText: 'Those who disbelieve and deny Our signs are companions of Hellfire.',
            ),
            Verse(
              verseKey: '5:33',
              surahNumber: 5,
              ayahNumber: 33,
              translationText: 'The recompense of those who wage war against Allah and His Messenger is severe.',
            ),
          ];
        },
        loadVerseTafsir: (int surahNumber, int ayahNumber) async {
          if (ayahNumber == 10) {
            return 'This verse warns that those who reject Allahs signs face the punishment of hell.';
          }
          if (ayahNumber == 33) {
            return 'This verse addresses war and violent corruption in the land.';
          }
          return null;
        },
        loadVerseTafsirSource: (int surahNumber, int ayahNumber) async => 'Test Tafsir',
      );

      final evidence = await service.retrieveGroundedEvidence(
        'hell in sura al maidah',
        limit: 1,
      );

      expect(evidence, hasLength(1));
      expect(evidence.single.verseKey, '5:10');
      expect(evidence.single.tafsirSource, 'Test Tafsir');
    });

    test('bidirectional synonym expansion matches reverse synonym values', () async {
      // "hellfire" is a VALUE in the 'hell' synonym entry.
      // Bidirectional expansion should still include 'jahannam', 'punishment', etc.
      // and the key term 'hell', which helps reranking pick the right verse.
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) {
          final results = <VectorSearchResult>[
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_generic',
                content: 'Translation: Be mindful of your duties.\nTafsir: A general reminder about daily life.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '4:1',
                },
              ),
              score: 0.90,
            ),
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_hell',
                content: 'Translation: Indeed, those who disbelieve will be in the fire of Hell.\nTafsir: This verse warns of the punishment of jahannam for those who reject faith.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '98:6',
                },
              ),
              score: 0.70,
            ),
          ];
          return filter == null
              ? results
              : results.where((item) => filter(item.entry)).toList(growable: false);
        },
      );

      final evidence = await service.retrieveGroundedEvidence(
        'hellfire',
        limit: 1,
      );

      // Even though 4:1 has a higher vector score, 98:6 should win because
      // bidirectional expansion of "hellfire" includes "hell", "jahannam",
      // "punishment" etc., all of which match 98:6's content.
      expect(evidence, hasLength(1));
      expect(evidence.single.verseKey, '98:6');
    });

    test('short query augmentation improves embedding for single-word queries', () async {
      String? capturedEmbeddingQuery;
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) {
          capturedEmbeddingQuery = text;
          return <VectorSearchResult>[
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_19_68',
                content: 'Translation: By your Lord, We will gather them and the devils.\nTafsir: A description of gathering the disbelievers with the devils around hell.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '19:68',
                },
              ),
              score: 0.80,
            ),
          ];
        },
      );

      await service.retrieveGroundedEvidence('hell', limit: 1);

      // The single-word query "hell" should be augmented with synonym terms
      // before being sent to the vector store for embedding.
      expect(capturedEmbeddingQuery, isNot(equals('hell')));
      expect(capturedEmbeddingQuery!.split(' ').length, greaterThan(1));
    });

    test('previously-stopped terms like dua now produce query terms', () async {
      // "dua" was previously in stop words, causing bare "dua" queries to
      // produce empty query terms and fail retrieval.
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) {
          return <VectorSearchResult>[
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_2_186',
                content: 'Translation: I am near. I respond to the invocation of the supplicant.\nTafsir: Allah answers dua and hears the call of sincere supplication.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '2:186',
                },
              ),
              score: 0.75,
            ),
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_generic',
                content: 'Translation: Eat from the good things.\nTafsir: A reminder about lawful food and provisions.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '2:168',
                },
              ),
              score: 0.80,
            ),
          ];
        },
      );

      final evidence = await service.retrieveGroundedEvidence('dua', limit: 1);

      // With "dua" no longer a stop word, it should produce query terms
      // that rerank 2:186 above the generic verse despite lower vector score.
      expect(evidence, hasLength(1));
      expect(evidence.single.verseKey, '2:186');
    });

    test('query terms matching a surah name are kept when no other terms exist', () async {
      // "cave" maps to surah 18 (Al-Kahf) in nameToNumber, but when it's
      // the only query word it should still be used as a content term
      // so that reranking can match verses mentioning "cave".
      final service = QuranRagService(
        queryVectors: (
          String text, {
          int topK = 5,
          bool Function(VectorEntry entry)? filter,
        }) {
          return <VectorSearchResult>[
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_18_10',
                content: 'Translation: When the youths retreated to the cave and said our Lord.\nTafsir: The young believers sought refuge in the cave to preserve their faith.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '18:10',
                },
              ),
              score: 0.70,
            ),
            VectorSearchResult(
              entry: VectorEntry(
                id: 'quran_generic',
                content: 'Translation: And establish prayer.\nTafsir: A general command about fulfilling prescribed worship.',
                vector: const <double>[],
                metadata: const <String, String>{
                  'kind': 'quran_corpus',
                  'verse_key': '2:43',
                },
              ),
              score: 0.80,
            ),
          ];
        },
        lexicalSearch: (_) async => const <Verse>[],
      );

      final evidence = await service.retrieveGroundedEvidence('cave', limit: 1);

      // "cave" should NOT be silently dropped as a surah name.
      // 18:10 mentions "cave" in both translation and tafsir,
      // so it should be ranked above the generic verse.
      expect(evidence, hasLength(1));
      expect(evidence.single.verseKey, '18:10');
    });
  });
}