import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'database_service.dart';
import 'vector_store_service.dart' show EmotionalVerse, kEmotionalVerses;

/// Manages a daily Quran emotional comfort / motivation notification.
class DailyNotificationService {
  DailyNotificationService._();
  static final DailyNotificationService instance = DailyNotificationService._();

  static const _channelId = 'noor_daily_reminder';
  static const _channelName = 'Daily Quran Comfort';
  static const _channelDescription = 'Daily emotional comfort and motivation from Quran';
  static const _notificationId = 1001;

  static const _prefEnabled = 'daily_notification_enabled';
  static const _prefHour = 'daily_notification_hour';
  static const _prefMinute = 'daily_notification_minute';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Whether the daily notification is currently enabled.
  bool _enabled = false;
  bool get enabled => _enabled;

  /// The scheduled hour (0–23).
  int _hour = 6;
  int get hour => _hour;

  /// The scheduled minute (0–59).
  int _minute = 0;
  int get minute => _minute;

  // ── Initialization ─────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) {
      if (_enabled) {
        await _scheduleDaily();
      }
      return;
    }
    _initialized = true;

    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation(_guessTimeZone()));
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefEnabled) ?? false;
    _hour = prefs.getInt(_prefHour) ?? 6;
    _minute = prefs.getInt(_prefMinute) ?? 0;

    if (_enabled) {
      await _scheduleDaily();
    }
  }

  // ── Public API ─────────────────────────────────────────────────────

  /// Request notification permission on platforms that need it; returns
  /// `true` if the user granted notification permission.
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidPlugin?.requestNotificationsPermission();
      if (granted != true) return false;
      // Also request exact alarm permission for reliable scheduling.
      await androidPlugin?.requestExactAlarmsPermission();
      return true;
    }
    if (Platform.isIOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return true;
  }

  /// Enable the daily reminder and schedule it at [hour]:[minute].
  Future<void> enable({required int hour, required int minute}) async {
    _enabled = true;
    _hour = hour;
    _minute = minute;
    await _persist();
    await _scheduleDaily();
  }

  /// Disable the daily reminder and cancel any pending notification.
  Future<void> disable() async {
    _enabled = false;
    await _persist();
    await _plugin.cancel(id: _notificationId);
  }

  /// Update only the reminder time without changing whether it is enabled.
  Future<void> setTime({required int hour, required int minute}) async {
    _hour = hour;
    _minute = minute;
    await _persist();
    if (_enabled) {
      await _scheduleDaily();
    }
  }

  /// Show an immediate test notification with today's emotional ayah.
  Future<void> showTestNotification() async {
    final content = await _dailyNotificationContent(DateTime.now());
    await _plugin.show(
      id: _notificationId + 1,
      title: content.title,
      body: content.body,
      notificationDetails: _notificationDetails(),
    );
  }

  // ── Private ────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, _enabled);
    await prefs.setInt(_prefHour, _hour);
    await prefs.setInt(_prefMinute, _minute);
  }

  Future<void> _scheduleDaily() async {
    await _plugin.cancel(id: _notificationId);
    final scheduledDate = _nextInstanceOfTime(_hour, _minute);
    final content = await _dailyNotificationContent(scheduledDate);

    // Determine best schedule mode: exact if permission granted, else inexact.
    AndroidScheduleMode scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final canExact = await androidPlugin?.canScheduleExactNotifications();
      if (canExact == true) {
        scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
      }
    }

    await _plugin.zonedSchedule(
      id: _notificationId,
      title: content.title,
      body: content.body,
      scheduledDate: scheduledDate,
      notificationDetails: _notificationDetails(),
      androidScheduleMode: scheduleMode,
      // Repeat daily at the same time.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<_NotificationContent> _dailyNotificationContent(DateTime day) async {
    final seededVerse = _dailyEmotionalVerse(day);
    final fallback = _buildNotificationFromSeed(seededVerse);

    try {
      final dateKey = _dateOnly(day);
      final daily = await DatabaseService.instance.getDailyAyah(dateKey);
      final text = daily?.translationText;
      if (text != null && text.isNotEmpty) {
        final verseKey = daily!.verseKey;
        return _NotificationContent(
          title: _titleForVerse(seededVerse),
          body: '$verseKey — ${_truncate(text, 150)}',
        );
      }
    } catch (_) {}

    return fallback;
  }

  EmotionalVerse _dailyEmotionalVerse(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    final index = date.difference(DateTime(2026, 1, 1)).inDays.abs() %
        kEmotionalVerses.length;
    return kEmotionalVerses[index];
  }

  _NotificationContent _buildNotificationFromSeed(EmotionalVerse verse) {
    return _NotificationContent(
      title: _titleForVerse(verse),
      body: '${verse.verseKey} — ${_truncate(verse.translationText, 150)}',
    );
  }

  String _titleForVerse(EmotionalVerse verse) {
    switch (verse.category) {
      case 'gratitude_blessings':
        return 'Daily Quran gratitude';
      case 'comfort_relief':
        return 'Comfort & relief from hardship';
      case 'calm_peace':
        return 'Calmness & peace of heart';
      case 'hope_trust':
        return 'Hope & trust in Allah';
      case 'mercy_forgiveness':
        return 'Mercy & forgiveness';
      case 'patience_strength':
        return 'Patience & strength';
    }

    final emotion = verse.emotion;
    if (emotion.contains('grateful') || emotion.contains('thankful')) {
      return 'Daily Quran gratitude';
    }
    if (emotion.contains('hopeless') || emotion.contains('sadness')) {
      return 'Daily Quran comfort';
    }
    if (emotion.contains('anxiety') || emotion.contains('fear')) {
      return 'Calm for your heart';
    }
    if (emotion.contains('patience') || emotion.contains('perseverance')) {
      return 'Daily Quran motivation';
    }
    if (emotion.contains('guilt') || emotion.contains('sin')) {
      return 'Mercy and hope from Quran';
    }
    return 'Daily comfort from Quran';
  }

  String _truncate(String text, int maxChars) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxChars) {
      return normalized;
    }
    return '${normalized.substring(0, maxChars - 3)}...';
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final dayValue = date.day.toString().padLeft(2, '0');
    return '$year-$month-$dayValue';
  }

  String _guessTimeZone() {
    try {
      final offset = DateTime.now().timeZoneOffset;
      // Best-effort mapping; timezone package will use UTC if not found.
      final hours = offset.inHours;
      const offsetToZone = <int, String>{
        -12: 'Pacific/Baker_Island',
        -11: 'Pacific/Pago_Pago',
        -10: 'Pacific/Honolulu',
        -9: 'America/Anchorage',
        -8: 'America/Los_Angeles',
        -7: 'America/Denver',
        -6: 'America/Chicago',
        -5: 'America/New_York',
        -4: 'America/Halifax',
        -3: 'America/Sao_Paulo',
        -2: 'Atlantic/South_Georgia',
        -1: 'Atlantic/Azores',
        0: 'Europe/London',
        1: 'Europe/Paris',
        2: 'Europe/Istanbul',
        3: 'Asia/Riyadh',
        4: 'Asia/Dubai',
        5: 'Asia/Karachi',
        6: 'Asia/Dhaka',
        7: 'Asia/Bangkok',
        8: 'Asia/Singapore',
        9: 'Asia/Tokyo',
        10: 'Australia/Sydney',
        11: 'Pacific/Noumea',
        12: 'Pacific/Auckland',
      };
      return offsetToZone[hours] ?? 'UTC';
    } catch (_) {
      return 'UTC';
    }
  }
}

class _NotificationContent {
  final String title;
  final String body;

  const _NotificationContent({
    required this.title,
    required this.body,
  });
}
