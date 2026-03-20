import 'dart:math';

import 'package:flutter/foundation.dart';

import 'embedding_service.dart';

/// In-memory vector store for conversational memory and emotional guidance.
/// Replaces zvec_flutter for cross-platform development; can swap to zvec for Android prod.
class VectorStoreService {
  VectorStoreService._();
  static final VectorStoreService instance = VectorStoreService._();

  final List<VectorEntry> _entries = [];
  bool _initialized = false;

  bool get isInitialized => _initialized;
  int get entryCount => _entries.length;

  Future<void> initialize() async {
    _initialized = true;
    debugPrint('VectorStore: Initialized (${_entries.length} entries)');
  }

  /// Insert a text entry with metadata
  void insert({
    required String id,
    required String content,
    required List<double> vector,
    Map<String, String>? metadata,
  }) {
    // Remove existing entry with same ID
    _entries.removeWhere((e) => e.id == id);
    _entries.add(VectorEntry(
      id: id,
      content: content,
      vector: vector,
      metadata: metadata ?? {},
    ));
  }

  /// Query for similar entries using cosine similarity
  List<VectorSearchResult> query(List<double> queryVector, {int topK = 5}) {
    if (_entries.isEmpty) return [];

    final scored = _entries.map((entry) {
      final score = _cosineSimilarity(queryVector, entry.vector);
      return VectorSearchResult(entry: entry, score: score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList();
  }

  /// Query by text (embed then search)
  List<VectorSearchResult> queryByText(String text, {int topK = 5}) {
    final vector = EmbeddingService.instance.embed(text);
    return query(vector, topK: topK);
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

  /// Seed emotional guidance verses
  Future<void> seedEmotionalVerses(List<EmotionalVerse> verses) async {
    for (final verse in verses) {
      final vector = EmbeddingService.instance.embed(
        '${verse.emotion} ${verse.translationText}',
      );
      insert(
        id: 'emotion_${verse.verseKey}',
        content: verse.translationText,
        vector: vector,
        metadata: {
          'verse_key': verse.verseKey,
          'emotion': verse.emotion,
          'arabic': verse.arabicText ?? '',
        },
      );
    }
    debugPrint('VectorStore: Seeded ${verses.length} emotional verses');
  }

  void clear() {
    _entries.clear();
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
