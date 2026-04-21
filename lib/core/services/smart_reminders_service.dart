import 'dart:async';
import 'dart:io';

import 'package:adhan/adhan.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'location_service.dart';

/// Schedules optional motivational reminders throughout the day:
///   • post-Fajr adhkar reminder (fires ~15 minutes after Fajr each morning)
///   • bedtime dua reminder (fires at a user-chosen hour/minute each night)
///
/// This service reuses the existing [FlutterLocalNotificationsPlugin]
/// initialization performed by `DailyNotificationService`. Call [initialize]
/// after that service's `initialize()` so that timezones and plugin settings
/// are already set up.
class SmartRemindersService {
  SmartRemindersService._();
  static final SmartRemindersService instance = SmartRemindersService._();

  // Notification ids (distinct from DailyNotificationService: 1001, 1002).
  static const int _idPostFajr = 1010;
  static const int _idBedtime = 1011;

  static const String _channelId = 'noor_smart_reminders';
  static const String _channelName = 'Smart Reminders';
  static const String _channelDescription =
      'Contextual reminders for morning adhkar and bedtime dua';

  // Preference keys.
  static const _prefPostFajrEnabled = 'smart.postfajr.enabled';
  static const _prefBedtimeEnabled = 'smart.bedtime.enabled';
  static const _prefBedtimeHour = 'smart.bedtime.hour';
  static const _prefBedtimeMinute = 'smart.bedtime.minute';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _postFajrEnabled = false;
  bool _bedtimeEnabled = false;
  int _bedtimeHour = 22;
  int _bedtimeMinute = 0;
  bool _initialized = false;

  bool get postFajrEnabled => _postFajrEnabled;
  bool get bedtimeEnabled => _bedtimeEnabled;
  int get bedtimeHour => _bedtimeHour;
  int get bedtimeMinute => _bedtimeMinute;

  Future<void> initialize() async {
    if (_initialized) {
      await _rescheduleAll();
      return;
    }
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _postFajrEnabled = prefs.getBool(_prefPostFajrEnabled) ?? false;
    _bedtimeEnabled = prefs.getBool(_prefBedtimeEnabled) ?? false;
    _bedtimeHour = prefs.getInt(_prefBedtimeHour) ?? 22;
    _bedtimeMinute = prefs.getInt(_prefBedtimeMinute) ?? 0;
    await _rescheduleAll();
  }

  Future<void> setPostFajrEnabled(bool enabled) async {
    _postFajrEnabled = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefPostFajrEnabled, enabled);
    if (enabled) {
      await _schedulePostFajr();
    } else {
      await _plugin.cancel(id: _idPostFajr);
    }
  }

  Future<void> setBedtime({
    required bool enabled,
    int? hour,
    int? minute,
  }) async {
    _bedtimeEnabled = enabled;
    if (hour != null) _bedtimeHour = hour;
    if (minute != null) _bedtimeMinute = minute;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefBedtimeEnabled, _bedtimeEnabled);
    await p.setInt(_prefBedtimeHour, _bedtimeHour);
    await p.setInt(_prefBedtimeMinute, _bedtimeMinute);
    if (_bedtimeEnabled) {
      await _scheduleBedtime();
    } else {
      await _plugin.cancel(id: _idBedtime);
    }
  }

  Future<void> _rescheduleAll() async {
    if (_postFajrEnabled) {
      await _schedulePostFajr();
    } else {
      await _plugin.cancel(id: _idPostFajr);
    }
    if (_bedtimeEnabled) {
      await _scheduleBedtime();
    } else {
      await _plugin.cancel(id: _idBedtime);
    }
  }

  Future<void> _schedulePostFajr() async {
    await _plugin.cancel(id: _idPostFajr);
    final pos = await LocationService.getCurrentPosition();
    if (pos == null) return; // cannot compute Fajr without location

    final coords = Coordinates(pos.latitude, pos.longitude);
    final params = CalculationMethod.muslim_world_league.getParameters();

    final now = DateTime.now();
    PrayerTimes times = PrayerTimes(
      coords,
      DateComponents.from(now),
      params,
    );
    // Post-Fajr target = Fajr + 15 minutes.
    DateTime target = times.fajr.add(const Duration(minutes: 15));
    if (target.isBefore(now)) {
      final tomorrow = now.add(const Duration(days: 1));
      final tTimes = PrayerTimes(
        coords,
        DateComponents.from(tomorrow),
        params,
      );
      target = tTimes.fajr.add(const Duration(minutes: 15));
    }

    final scheduled = tz.TZDateTime.from(target, tz.local);
    await _plugin.zonedSchedule(
      id: _idPostFajr,
      title: 'Morning Adhkar',
      body:
          'Start your day with remembrance. The morning adhkar are waiting 🌅',
      scheduledDate: scheduled,
      notificationDetails: _details(),
      androidScheduleMode: await _bestScheduleMode(),
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _scheduleBedtime() async {
    await _plugin.cancel(id: _idBedtime);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _bedtimeHour,
      _bedtimeMinute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: _idBedtime,
      title: 'Before Sleep',
      body:
          'Recite Āyat al-Kursī and the bedtime duas. Sleep in the remembrance of Allah 🌙',
      scheduledDate: scheduled,
      notificationDetails: _details(),
      androidScheduleMode: await _bestScheduleMode(),
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<AndroidScheduleMode> _bestScheduleMode() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final canExact = await android?.canScheduleExactNotifications();
      if (canExact == true) return AndroidScheduleMode.exactAllowWhileIdle;
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
  }
}
