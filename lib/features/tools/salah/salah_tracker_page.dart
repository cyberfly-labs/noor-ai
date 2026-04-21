import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

class SalahTrackerPage extends StatefulWidget {
  const SalahTrackerPage({super.key});

  @override
  State<SalahTrackerPage> createState() => _SalahTrackerPageState();
}

class _SalahTrackerPageState extends State<SalahTrackerPage> {
  static const _key = 'salah.tracker.v1';
  static const _prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

  SharedPreferences? _prefs;
  // date key -> Set of prayer names prayed.
  Map<String, Set<String>> _data = {};
  DateTime _cursor = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dk(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    final m = <String, Set<String>>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) =>
            m[k] = (v as List).map((e) => e.toString()).toSet());
      } catch (_) {}
    }
    setState(() {
      _prefs = p;
      _data = m;
    });
  }

  Future<void> _save() async {
    final encoded =
        jsonEncode(_data.map((k, v) => MapEntry(k, v.toList())));
    await _prefs?.setString(_key, encoded);
  }

  Future<void> _toggle(DateTime d, String name) async {
    final k = _dk(d);
    final set = _data[k] ?? <String>{};
    if (set.contains(name)) {
      set.remove(name);
    } else {
      set.add(name);
      HapticFeedback.lightImpact();
    }
    _data[k] = set;
    setState(() {});
    await _save();
  }

  int _currentStreak() {
    int n = 0;
    DateTime d = DateTime.now();
    while (true) {
      final set = _data[_dk(d)] ?? <String>{};
      if (set.length < _prayers.length) break;
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  int _monthlyCount() {
    int n = 0;
    _data.forEach((k, v) {
      final parts = k.split('-');
      if (parts.length != 3) return;
      if (int.parse(parts[0]) == _cursor.year &&
          int.parse(parts[1]) == _cursor.month) {
        n += v.length;
      }
    });
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayKey = _dk(today);
    final todaySet = _data[todayKey] ?? <String>{};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Salah Tracker')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).padding.bottom + 80),
          children: [
            _stats(),
            const SizedBox(height: 20),
            const Text('Today',
                style: TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ..._prayers.map((p) => _prayerTile(today, p, todaySet.contains(p))),
            const SizedBox(height: 20),
            _monthHeader(),
            const SizedBox(height: 8),
            _grid(today),
            const SizedBox(height: 10),
            const Text(
              'Tap a cell to expand and mark which prayers were performed.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stats() {
    final streak = _currentStreak();
    final monthly = _monthlyCount();
    return Row(
      children: [
        Expanded(
            child: _statCard('$streak', 'Full days streak',
                Icons.local_fire_department_rounded)),
        const SizedBox(width: 10),
        Expanded(
            child: _statCard('$monthly', 'Prayers this month',
                Icons.calendar_view_month_rounded)),
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
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _prayerTile(DateTime day, String name, bool checked) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: checked ? AppColors.gold10 : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: checked ? AppColors.gold30 : AppColors.divider, width: 0.8),
      ),
      child: CheckboxListTile(
        value: checked,
        onChanged: (_) => _toggle(day, name),
        activeColor: AppColors.gold,
        checkColor: Colors.black,
        title: Text(name,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  Widget _monthHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => setState(() =>
              _cursor = DateTime(_cursor.year, _cursor.month - 1, 1)),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Center(
            child: Text(
              '${_monthName(_cursor.month)} ${_cursor.year}',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton(
          onPressed: () => setState(() =>
              _cursor = DateTime(_cursor.year, _cursor.month + 1, 1)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _grid(DateTime today) {
    final first = DateTime(_cursor.year, _cursor.month, 1);
    final daysInMonth = DateTime(_cursor.year, _cursor.month + 1, 0).day;
    final leading = first.weekday % 7;

    final cells = <Widget>[];
    for (int i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_cursor.year, _cursor.month, d);
      final set = _data[_dk(date)] ?? <String>{};
      final ratio = set.length / _prayers.length;
      final future = date.isAfter(DateTime(today.year, today.month, today.day));

      cells.add(GestureDetector(
        onTap: future ? null : () => _showDay(date),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: ratio == 1
                    ? AppColors.gold
                    : (ratio > 0 ? AppColors.gold30 : AppColors.divider),
                width: 0.8),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.bottomCenter,
                  heightFactor: ratio,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.gold25,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
              Center(
                child: Text('$d',
                    style: TextStyle(
                      color: future ? AppColors.textMuted : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    )),
              ),
            ],
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

  void _showDay(DateTime day) {
    final set = _data[_dk(day)] ?? <String>{};
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_monthName(day.month)} ${day.day}, ${day.year}',
                    style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                ..._prayers.map(
                  (p) => CheckboxListTile(
                    value: set.contains(p),
                    onChanged: (v) async {
                      await _toggle(day, p);
                      setSheet(() {
                        if (set.contains(p)) {
                          set.remove(p);
                        } else {
                          set.add(p);
                        }
                      });
                    },
                    activeColor: AppColors.gold,
                    checkColor: Colors.black,
                    title: Text(p,
                        style: const TextStyle(color: AppColors.textPrimary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
