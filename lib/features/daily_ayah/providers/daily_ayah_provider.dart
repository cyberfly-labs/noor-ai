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
    String? reflection,
    String? explanation,
    bool? isExplaining,
  }) {
    return DailyAyahState(
      dailyAyah: dailyAyah ?? this.dailyAyah,
      verse: verse ?? this.verse,
      streak: streak ?? this.streak,
      isLoading: isLoading ?? this.isLoading,
      reflection: reflection ?? this.reflection,
      explanation: explanation ?? this.explanation,
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

      final prompt = PromptTemplates.explainVerse(
        arabicText: verse.arabicText ?? '',
        translationText: verse.translationText ?? '',
        tafsirText: tafsir,
        tafsirSource: tafsirSource,
      );

      await _llm.initialize();

      final buffer = StringBuffer();
      await for (final token in _llm.generate(prompt)) {
        buffer.write(token);
        state = state.copyWith(
          explanation: buffer.toString(),
          isExplaining: true,
        );
      }

      state = state.copyWith(isExplaining: false);
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
}

final dailyAyahProvider =
    StateNotifierProvider<DailyAyahNotifier, DailyAyahState>((ref) {
  return DailyAyahNotifier();
});
