import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'database_service.dart';

/// Manages a daily Quran reading reminder notification.
///
/// The notification is scheduled to repeat every day at a user-chosen time.
/// When the user opens the notification the app navigates to the Daily Ayah
/// page.
class DailyNotificationService {
  DailyNotificationService._();
  static final DailyNotificationService instance = DailyNotificationService._();

  static const _channelId = 'noor_daily_reminder';
  static const _channelName = 'Daily Quran Reminder';
  static const _channelDescription = 'Daily notification reminding you to read Quran';
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
    if (_initialized) return;
    _initialized = true;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(_guessTimeZone()));

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
      return granted ?? false;
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

  /// Show an immediate test notification with today's daily ayah.
  Future<void> showTestNotification() async {
    final body = await _todayAyahBody();
    await _plugin.show(
      id: _notificationId + 1,
      title: 'Time to Read Quran',
      body: body,
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

    final body = await _todayAyahBody();

    await _plugin.zonedSchedule(
      id: _notificationId,
      title: 'Time to Read Quran',
      body: body,
      scheduledDate: _nextInstanceOfTime(_hour, _minute),
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
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

  Future<String> _todayAyahBody() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final daily = await DatabaseService.instance.getDailyAyah(today);
      final text = daily?.translationText;
      if (text != null && text.isNotEmpty) {
        final translation = text.length > 120
            ? '${text.substring(0, 117)}...'
            : text;
        return '${daily!.verseKey} — $translation';
      }
    } catch (_) {}
    return 'Open Noor AI to read your verse for today.';
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
