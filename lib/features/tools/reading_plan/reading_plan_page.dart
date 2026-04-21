import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

/// Simple khatm (Quran finish) planner using 604 Madinah-script pages.
class ReadingPlanPage extends StatefulWidget {
  const ReadingPlanPage({super.key});

  @override
  State<ReadingPlanPage> createState() => _ReadingPlanPageState();
}

class _ReadingPlanPageState extends State<ReadingPlanPage> {
  static const int _totalPages = 604;
  static const _kStart = 'reading_plan.start';
  static const _kDays = 'reading_plan.days';
  static const _kPagesRead = 'reading_plan.pages_read';

  SharedPreferences? _prefs;
  DateTime? _start;
  int _days = 30;
  int _pagesRead = 0;

  int get _dayIndex {
    if (_start == null) return 1;
    final d = DateTime.now().difference(_start!).inDays + 1;
    return d.clamp(1, _days);
  }

  int get _pagesPerDay => (_totalPages / _days).ceil();
  int get _expected =>
      (_pagesPerDay * _dayIndex).clamp(0, _totalPages).toInt();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final startMs = p.getInt(_kStart);
    setState(() {
      _prefs = p;
      _start = startMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(startMs);
      _days = p.getInt(_kDays) ?? 30;
      _pagesRead = p.getInt(_kPagesRead) ?? 0;
    });
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    if (_start != null) {
      await p.setInt(_kStart, _start!.millisecondsSinceEpoch);
    } else {
      await p.remove(_kStart);
    }
    await p.setInt(_kDays, _days);
    await p.setInt(_kPagesRead, _pagesRead);
  }

  void _startPlan(int days) {
    setState(() {
      _days = days;
      _start = DateTime.now();
      _pagesRead = 0;
    });
    _save();
  }

  void _reset() {
    setState(() {
      _start = null;
      _pagesRead = 0;
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reading Plan')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).padding.bottom + 80),
          children: [
            if (_start == null) ..._buildStartUi() else ..._buildActiveUi(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStartUi() {
    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gold15),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.menu_book_rounded, color: AppColors.gold, size: 32),
            SizedBox(height: 10),
            Text(
              'Finish the Quran',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 6),
            Text(
              'Choose a plan length. The 604-page Madinah mushaf is divided '
              'evenly across your chosen days.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _planOption(7, '~86 pages / day', 'Intensive'),
      _planOption(30, '~21 pages / day', 'Ramadan pace'),
      _planOption(60, '~11 pages / day', 'Steady'),
      _planOption(90, '~7 pages / day', 'Relaxed'),
      _planOption(180, '~4 pages / day', 'Gentle'),
    ];
  }

  Widget _planOption(int days, String rate, String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _startPlan(days),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.gold15),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.goldGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text('$days',
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 18)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700)),
                      Text(rate,
                          style: const TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActiveUi() {
    final progress = _pagesRead / _totalPages;
    final onTrack = _pagesRead >= _expected;
    final todayLeft = (_expected - _pagesRead).clamp(0, _totalPages);

    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.goldGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Khatm plan',
                style: TextStyle(
                    color: Colors.black87, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('$_pagesRead / $_totalPages pages',
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.white24,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Day $_dayIndex of $_days • '
              '${onTrack ? "On track" : "$todayLeft pages behind"}',
              style: const TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _infoRow('Target today', '$_pagesPerDay pages'),
      _infoRow('Read today',
          '${(_pagesRead - (_pagesPerDay * (_dayIndex - 1))).clamp(0, _pagesPerDay)}'),
      _infoRow('Remaining', '${_totalPages - _pagesRead} pages'),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pagesRead > 0
                  ? () {
                      setState(() => _pagesRead--);
                      _save();
                    }
                  : null,
              icon: const Icon(Icons.remove_rounded),
              label: const Text('−1 page'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _pagesRead < _totalPages
                  ? () {
                      setState(() => _pagesRead++);
                      _save();
                    }
                  : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('+1 page'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () {
          setState(() => _pagesRead =
              (_pagesRead + _pagesPerDay).clamp(0, _totalPages));
          _save();
        },
        icon: const Icon(Icons.done_all_rounded),
        label: Text('Mark today\'s $_pagesPerDay pages read'),
      ),
      const SizedBox(height: 20),
      TextButton.icon(
        onPressed: _reset,
        icon: const Icon(Icons.restart_alt_rounded,
            color: AppColors.textMuted),
        label: const Text('Reset plan',
            style: TextStyle(color: AppColors.textMuted)),
      ),
    ];
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(color: AppColors.textMuted))),
            Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
