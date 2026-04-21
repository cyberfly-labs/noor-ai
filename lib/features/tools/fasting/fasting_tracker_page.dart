import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

/// Tracks voluntary and obligatory fasts by storing date keys in SharedPrefs.
class FastingTrackerPage extends StatefulWidget {
  const FastingTrackerPage({super.key});

  @override
  State<FastingTrackerPage> createState() => _FastingTrackerPageState();
}

class _FastingTrackerPageState extends State<FastingTrackerPage> {
  static const _key = 'fasting.completed';
  SharedPreferences? _prefs;
  Set<String> _completed = {};
  DateTime _monthCursor = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _prefs = p;
      _completed = p.getStringList(_key)?.toSet() ?? <String>{};
    });
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

  Future<void> _toggle(DateTime day) async {
    final k = _dateKey(day);
    setState(() {
      if (_completed.contains(k)) {
        _completed.remove(k);
      } else {
        _completed.add(k);
      }
    });
    await _prefs?.setStringList(_key, _completed.toList());
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final streak = _currentStreak(today);
    final monthCount = _completed.where((k) {
      final parts = k.split('-');
      return parts.length == 3 &&
          int.parse(parts[0]) == _monthCursor.year &&
          int.parse(parts[1]) == _monthCursor.month;
    }).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Fasting Tracker')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).padding.bottom + 80),
          children: [
            _stats(streak, monthCount),
            const SizedBox(height: 20),
            _monthNav(),
            const SizedBox(height: 8),
            _grid(today),
            const SizedBox(height: 16),
            const Text('Sunnah fasts',
                style: TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _tip('Mondays and Thursdays',
                'The Prophet ﷺ fasted these days regularly.'),
            _tip('13th, 14th, 15th of each Hijri month',
                'Ayyam al-Bidh (the white days).'),
            _tip('Day of Arafah (9 Dhu al-Hijjah)',
                'Expiates sins of the previous and coming year.'),
            _tip('Day of Ashura (10 Muharram)',
                'Expiates sins of the previous year.'),
            _tip('Six days of Shawwal',
                'Rewarded as if fasting the entire year.'),
          ],
        ),
      ),
    );
  }

  Widget _stats(int streak, int monthCount) {
    return Row(
      children: [
        Expanded(child: _statCard('$streak', 'Current streak', Icons.local_fire_department_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('$monthCount', 'This month', Icons.calendar_view_month_rounded)),
        const SizedBox(width: 10),
        Expanded(
            child:
                _statCard('${_completed.length}', 'Total', Icons.emoji_events_rounded)),
      ],
    );
  }

  Widget _statCard(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold15),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.gold),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _monthNav() {
    return Row(
      children: [
        IconButton(
          onPressed: () => setState(() => _monthCursor =
              DateTime(_monthCursor.year, _monthCursor.month - 1, 1)),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Center(
            child: Text(
                '${_monthName(_monthCursor.month)} ${_monthCursor.year}',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _monthCursor =
              DateTime(_monthCursor.year, _monthCursor.month + 1, 1)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _grid(DateTime today) {
    final first = DateTime(_monthCursor.year, _monthCursor.month, 1);
    final daysInMonth =
        DateTime(_monthCursor.year, _monthCursor.month + 1, 0).day;
    final leading = first.weekday % 7;

    final cells = <Widget>[];
    for (int i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_monthCursor.year, _monthCursor.month, d);
      final key = _dateKey(date);
      final done = _completed.contains(key);
      final future = date.isAfter(DateTime(today.year, today.month, today.day));

      cells.add(GestureDetector(
        onTap: future ? null : () => _toggle(date),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: done ? AppColors.gold : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: done
                    ? AppColors.goldLight
                    : (future ? AppColors.divider : AppColors.gold30),
                width: 0.8),
          ),
          child: Center(
            child: Text('$d',
                style: TextStyle(
                  color: done
                      ? Colors.black
                      : (future
                          ? AppColors.textMuted
                          : AppColors.textPrimary),
                  fontWeight: FontWeight.w700,
                )),
          ),
        ),
      ));
    }

    const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Column(
      children: [
        Row(
          children: weekdays
              .map((w) => Expanded(
                    child: Center(
                      child: Text(w,
                          style: const TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w700)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ],
    );
  }

  Widget _tip(String title, String body) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(body,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );

  int _currentStreak(DateTime today) {
    int streak = 0;
    DateTime d = DateTime(today.year, today.month, today.day);
    while (_completed.contains(_dateKey(d))) {
      streak++;
      d = d.subtract(const Duration(days: 1));
    }
    return streak;
  }

  String _monthName(int m) => const [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ][m - 1];
}
