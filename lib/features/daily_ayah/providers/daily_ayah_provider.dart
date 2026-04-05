import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/daily_ayah.dart';
import '../../../core/models/verse.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/daily_ayah_widget_service.dart';
import '../../../core/services/llm_service.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/services/quran_user_sync_service.dart';
import '../../../core/utils/prompt_templates.dart';

class DailyAyahState {
  static const Object _unset = Object();

  final DailyAyah? dailyAyah;
  final Verse? verse;
  final int streak;
  final bool isLoading;
  final String? reflection;
  final String? explanation;
  final bool isExplaining;

  const DailyAyahState({
    this.dailyAyah,
    this.verse,
    this.streak = 0,
    this.isLoading = false,
    this.reflection,
    this.explanation,
    this.isExplaining = false,
  });

  DailyAyahState copyWith({
    DailyAyah? dailyAyah,
    Verse? verse,
    int? streak,
    bool? isLoading,
    Object? reflection = _unset,
    Object? explanation = _unset,
    bool? isExplaining,
  }) {
    return DailyAyahState(
      dailyAyah: dailyAyah ?? this.dailyAyah,
      verse: verse ?? this.verse,
      streak: streak ?? this.streak,
      isLoading: isLoading ?? this.isLoading,
      reflection: identical(reflection, _unset)
          ? this.reflection
          : reflection as String?,
      explanation: identical(explanation, _unset)
          ? this.explanation
          : explanation as String?,
      isExplaining: isExplaining ?? this.isExplaining,
    );
  }
}

class DailyAyahNotifier extends StateNotifier<DailyAyahState> {
  DailyAyahNotifier() : super(const DailyAyahState());

  final _db = DatabaseService.instance;
  final _api = QuranApiService.instance;
  final _llm = LlmService.instance;
  final _sync = QuranUserSyncService.instance;

  Future<void> load({bool forceRefresh = false}) async {
    state = state.copyWith(isLoading: true);

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    // Check if we already have today's ayah
    var daily = await _db.getDailyAyah(todayStr);

    if (daily == null || forceRefresh) {
      // Fetch a random verse
      final verse = await _api.getRandomVerse();
      if (verse != null) {
        daily = DailyAyah(
          id: todayStr.hashCode.toString(),
          verseKey: verse.verseKey,
          arabicText: verse.arabicText ?? '',
          translationText: verse.translationText ?? '',
          date: todayStr,
        );
        await _db.insertDailyAyah(daily);
      }
    }

    // Record streak
    await _db.recordStreak(todayStr);
    var streak = await _db.getCurrentStreak();

    Verse? verse;
    if (daily != null) {
      verse = Verse(
        verseKey: daily.verseKey,
        surahNumber: int.tryParse(daily.verseKey.split(':').first) ?? 0,
        ayahNumber: int.tryParse(daily.verseKey.split(':').last) ?? 0,
        arabicText: daily.arabicText,
        translationText: daily.translationText,
      );
    }

    if (verse != null && await _sync.isReadyForSync) {
      try {
        await _sync.updateReadingSession(verse);
        await _sync.recordActivityForVerse(verse, date: todayStr);
        final remoteStreak = await _sync.fetchCurrentStreakDays();
        if (remoteStreak != null && remoteStreak > streak) {
          streak = remoteStreak;
        }
      } catch (error) {
        debugPrint('DailyAyah: Remote sync skipped: $error');
      }
    }

    state = DailyAyahState(
      dailyAyah: daily,
      verse: verse,
      streak: streak,
      isLoading: false,
    );

    if (verse != null) {
      await DailyAyahWidgetService.instance.updateVerse(verse);
    }
  }

  void setReflection(String text) {
    state = state.copyWith(reflection: text);
  }

  Future<void> explainVerse() async {
    final verse = state.verse;
    if (verse == null) return;

    // If already explained, just toggle visibility
    if (state.explanation != null && state.explanation!.isNotEmpty) {
      state = state.copyWith(explanation: null, isExplaining: false);
      return;
    }

    state = state.copyWith(isExplaining: true, explanation: '');

    try {
      final tafsir = await _api.getVerseTafsir(
        verse.surahNumber,
        verse.ayahNumber,
      );
      final tafsirSource = await _api.getVerseTafsirSource(
        verse.surahNumber,
        verse.ayahNumber,
      );

      final prompt = PromptTemplates.dailyAyahExplanation(
        verseKey: verse.verseKey,
        arabicText: verse.arabicText ?? '',
        translationText: verse.translationText ?? '',
        tafsirText: tafsir,
        tafsirSource: tafsirSource,
      );

      await _llm.initialize();

      final rawExplanation = await _llm.generateComplete(prompt);
      final cleanedExplanation = _finalizeExplanation(
        rawExplanation,
        verse: verse,
        tafsirText: tafsir,
        tafsirSource: tafsirSource,
      );
      state = state.copyWith(
        explanation: cleanedExplanation,
        isExplaining: false,
      );
    } catch (error) {
      debugPrint('DailyAyah: Explain failed: $error');
      state = state.copyWith(
        explanation: 'Could not generate explanation. Please try again.',
        isExplaining: false,
      );
    }
  }

  Future<void> syncRemoteState() async {
    final verse = state.verse;
    final dailyAyah = state.dailyAyah;
    if (verse == null || dailyAyah == null || !await _sync.isReadyForSync) {
      return;
    }

    try {
      await _sync.updateReadingSession(verse);
      await _sync.recordActivityForVerse(verse, date: dailyAyah.date);
      final remoteStreak = await _sync.fetchCurrentStreakDays();
      if (remoteStreak != null) {
        state = state.copyWith(streak: remoteStreak);
      }
    } catch (error) {
      debugPrint('DailyAyah: Manual sync skipped: $error');
    }
  }

  String _cleanGeneratedExplanation(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final extractedSections = _extractExplanationSections(trimmed);
    final sectionNormalized = extractedSections
        .replaceAll(RegExp(r'^\s*(?:📖\s*)?Quran:\s*$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*(?:📚\s*)?Explanation:\s*$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*(?:✨\s*)?Summary:\s*$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\[[^\]]+\]\s*$', multiLine: true), '')
        .replaceAll(
          RegExp(
            r"^\s*(match the user's language|do not repeat\.?|return only the explanation\.?|structure your response.*|grounded explanation in .*|each sentence must add new information\.?|quote the verse and reference\.?|short takeaway sentence\.?)\s*$",
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .trim();

    final normalizedWords = sectionNormalized
        .replaceAllMapped(
          RegExp(r'\b(\w+)(\s+\1\b)+', caseSensitive: false),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();

    final segments = normalizedWords
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    final uniqueSegments = <String>[];
    final seenNormalizedSegments = <String>{};
    for (final segment in segments) {
      final normalizedSegment = segment
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (normalizedSegment.isEmpty ||
          !seenNormalizedSegments.add(normalizedSegment)) {
        continue;
      }
      uniqueSegments.add(segment);
    }

    return uniqueSegments.join('\n\n').trim();
  }

  String _extractExplanationSections(String text) {
    final explanationMatch = RegExp(
      r'(?:📚\s*)?Explanation:\s*(.*?)(?=(?:✨\s*)?Summary:|$)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    final summaryMatch = RegExp(
      r'(?:✨\s*)?Summary:\s*(.*)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);

    if (explanationMatch == null && summaryMatch == null) {
      return text;
    }

    final parts = <String>[];
    final explanation = explanationMatch?.group(1)?.trim();
    if (explanation != null && explanation.isNotEmpty) {
      parts.add(explanation);
    }
    final summary = summaryMatch?.group(1)?.trim();
    if (summary != null && summary.isNotEmpty) {
      parts.add(summary);
    }
    return parts.join('\n\n').trim();
  }

  bool _looksLikePromptScaffold(String text) {
    if (text.isEmpty) {
      return true;
    }

    final normalized = text.toLowerCase();
    const scaffoldMarkers = <String>{
      'quote the verse and reference',
      'grounded explanation in 4-6 sentences',
      'each sentence must add new information',
      'short takeaway sentence',
      'match the user\'s language',
      'do not repeat',
      'return only the explanation',
      'structure your response',
    };

    if (scaffoldMarkers.any(normalized.contains)) {
      return true;
    }

    return RegExp(r'\[[^\]]+\]').hasMatch(text);
  }

  String _finalizeExplanation(
    String rawText, {
    required Verse verse,
    String? tafsirText,
    String? tafsirSource,
  }) {
    final cleaned = _cleanGeneratedExplanation(rawText);
    if (cleaned.length >= 80 && !_looksLikePromptScaffold(cleaned)) {
      return cleaned;
    }

    debugPrint(
      'DailyAyah: explanation scaffold detected, using tafsir-backed fallback for ${verse.verseKey}',
    );
    return _fallbackExplanation(
      verse: verse,
      tafsirText: tafsirText,
      tafsirSource: tafsirSource,
    );
  }

  String _fallbackExplanation({
    required Verse verse,
    String? tafsirText,
    String? tafsirSource,
  }) {
    final translation = (verse.translationText ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final normalizedTafsir = (tafsirText ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final tafsirSnippet = _truncateSentences(normalizedTafsir, maxSentences: 3);
    final source = (tafsirSource ?? '').trim().isEmpty
        ? 'the local tafsir'
        : tafsirSource!.trim();

    final paragraphs = <String>[];
    if (translation.isNotEmpty) {
      paragraphs.add('Verse ${verse.verseKey} says: "$translation"');
    }
    if (tafsirSnippet.isNotEmpty) {
      paragraphs.add('According to $source, $tafsirSnippet');
    }

    if (paragraphs.isEmpty) {
      return 'Verse ${verse.verseKey} invites reflection, but the local explanation text is limited right now.';
    }

    return paragraphs.join('\n\n');
  }

  String _truncateSentences(String text, {required int maxSentences}) {
    if (text.isEmpty) {
      return text;
    }

    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .take(maxSentences)
        .toList(growable: false);

    if (sentences.isEmpty) {
      final maxChars = text.length > 320 ? 320 : text.length;
      return text.substring(0, maxChars).trim();
    }

    return sentences.join(' ');
  }
}

final dailyAyahProvider =
    StateNotifierProvider<DailyAyahNotifier, DailyAyahState>((ref) {
  return DailyAyahNotifier();
});
