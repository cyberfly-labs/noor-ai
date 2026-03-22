import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/daily_ayah.dart';
import '../models/verse.dart';
import 'database_service.dart';
import 'quran_api_service.dart';

class DailyAyahWidgetService {
  DailyAyahWidgetService._();

  static final DailyAyahWidgetService instance = DailyAyahWidgetService._();
  static const MethodChannel _channel = MethodChannel(
    'com.noor.noor_ai/daily_ayah_widget',
  );

  Future<void> syncTodayAyahWidget() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final db = DatabaseService.instance;
    var dailyAyah = await db.getDailyAyah(today);

    if (dailyAyah == null) {
      final verse = await QuranApiService.instance.getRandomVerse();
      if (verse == null) {
        return;
      }
      dailyAyah = DailyAyah(
        id: today.hashCode.toString(),
        verseKey: verse.verseKey,
        arabicText: verse.arabicText ?? '',
        translationText: verse.translationText ?? '',
        date: today,
      );
      await db.insertDailyAyah(dailyAyah);
    }

    await updateVerse(
      Verse(
        verseKey: dailyAyah.verseKey,
        surahNumber: int.tryParse(dailyAyah.verseKey.split(':').first) ?? 0,
        ayahNumber: int.tryParse(dailyAyah.verseKey.split(':').last) ?? 0,
        arabicText: dailyAyah.arabicText,
        translationText: dailyAyah.translationText,
      ),
    );
  }

  Future<void> updateVerse(Verse verse) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('updateDailyAyahWidget', <String, String>{
        'verseKey': verse.verseKey,
        'arabicText': (verse.arabicText ?? '').trim(),
        'translationText': (verse.translationText ?? '').trim(),
      });
    } catch (error) {
      debugPrint('DailyAyahWidget: update skipped: $error');
    }
  }
}