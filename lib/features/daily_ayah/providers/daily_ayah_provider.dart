import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/daily_ayah.dart';
import '../../../core/models/verse.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/services/quran_user_sync_service.dart';

class DailyAyahState {
  final DailyAyah? dailyAyah;
  final Verse? verse;
  final int streak;
  final bool isLoading;
  final String? reflection;

  const DailyAyahState({
    this.dailyAyah,
    this.verse,
    this.streak = 0,
    this.isLoading = false,
    this.reflection,
  });

  DailyAyahState copyWith({
    DailyAyah? dailyAyah,
    Verse? verse,
    int? streak,
    bool? isLoading,
    String? reflection,
  }) {
    return DailyAyahState(
      dailyAyah: dailyAyah ?? this.dailyAyah,
      verse: verse ?? this.verse,
      streak: streak ?? this.streak,
      isLoading: isLoading ?? this.isLoading,
      reflection: reflection ?? this.reflection,
    );
  }
}

class DailyAyahNotifier extends StateNotifier<DailyAyahState> {
  DailyAyahNotifier() : super(const DailyAyahState());

  final _db = DatabaseService.instance;
  final _api = QuranApiService.instance;
  final _sync = QuranUserSyncService.instance;

  Future<void> load() async {
    state = state.copyWith(isLoading: true);

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    // Check if we already have today's ayah
    var daily = await _db.getDailyAyah(todayStr);

    if (daily == null) {
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
  }

  void setReflection(String text) {
    state = state.copyWith(reflection: text);
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
