import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';

import '../../../core/theme/app_theme.dart';

class HijriCalendarPage extends StatefulWidget {
  const HijriCalendarPage({super.key});

  @override
  State<HijriCalendarPage> createState() => _HijriCalendarPageState();
}

class _HijriCalendarPageState extends State<HijriCalendarPage> {
  late DateTime _cursor;

  static const _hijriMonths = [
    'Muharram',
    'Safar',
    "Rabi' al-Awwal",
    "Rabi' al-Thani",
    'Jumada al-Awwal',
    'Jumada al-Thani',
    'Rajab',
    "Sha'ban",
    'Ramadan',
    'Shawwal',
    "Dhu al-Qi'dah",
    'Dhu al-Hijjah',
  ];

  static const _important = <int, List<(int, String)>>{
    1: [(1, "Islamic New Year"), (10, 'Day of Ashura')],
    3: [(12, "Mawlid an-Nabi")],
    7: [(27, "Laylat al-Mi'raj")],
    8: [(15, "Laylat al-Bara'at")],
    9: [(1, 'First of Ramadan'), (27, 'Laylat al-Qadr (odd night)')],
    10: [(1, 'Eid al-Fitr')],
    12: [(9, 'Day of Arafah'), (10, 'Eid al-Adha')],
  };

  @override
  void initState() {
    super.initState();
    _cursor = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final hijriToday = HijriCalendar.fromDate(today);
    final hijriCursor = HijriCalendar.fromDate(_cursor);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Hijri Calendar')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).padding.bottom + 80),
          children: [
            _todayCard(today, hijriToday),
            const SizedBox(height: 16),
            _monthHeader(hijriCursor),
            const SizedBox(height: 10),
            _monthGrid(hijriCursor, today),
            const SizedBox(height: 20),
            const Text('Important days this month',
                style: TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._important[hijriCursor.hMonth]?.map(
                  (d) => _eventTile('${d.$1} ${_hijriMonths[hijriCursor.hMonth - 1]}',
                      d.$2),
                ) ??
                [const Text('No marked events',
                    style: TextStyle(color: AppColors.textMuted))],
          ],
        ),
      ),
    );
  }

  Widget _todayCard(DateTime today, HijriCalendar h) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Today',
              style: TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            '${h.hDay} ${_hijriMonths[h.hMonth - 1]} ${h.hYear} AH',
            style: const TextStyle(
                color: Colors.black,
                fontSize: 22,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${today.day}/${today.month}/${today.year}',
            style: const TextStyle(color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _monthHeader(HijriCalendar h) {
    return Row(
      children: [
        IconButton(
          onPressed: () => setState(() {
            _cursor = DateTime(_cursor.year, _cursor.month - 1, _cursor.day);
          }),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Center(
            child: Text(
              '${_hijriMonths[h.hMonth - 1]} ${h.hYear} AH',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton(
          onPressed: () => setState(() {
            _cursor = DateTime(_cursor.year, _cursor.month + 1, _cursor.day);
          }),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _monthGrid(HijriCalendar cursor, DateTime today) {
    // Grid shows Gregorian calendar days of the month cursor points to,
    // annotated with Hijri day numbers — pragmatic and predictable.
    final first = DateTime(_cursor.year, _cursor.month, 1);
    final daysInMonth =
        DateTime(_cursor.year, _cursor.month + 1, 0).day;
    final leading = first.weekday % 7; // Sun = 0

    final cells = <Widget>[];
    for (int i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_cursor.year, _cursor.month, d);
      final h = HijriCalendar.fromDate(date);
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      cells.add(
        Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isToday ? AppColors.gold15 : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isToday ? AppColors.gold : AppColors.divider,
                width: isToday ? 1.2 : 0.6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$d',
                style: TextStyle(
                  color: isToday ? AppColors.gold : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${h.hDay}',
                style: TextStyle(
                  color: isToday ? AppColors.gold : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
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
          childAspectRatio: 0.85,
          children: cells,
        ),
      ],
    );
  }

  Widget _eventTile(String date, String name) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: AppColors.gold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700)),
                Text(date,
                    style: const TextStyle(color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
