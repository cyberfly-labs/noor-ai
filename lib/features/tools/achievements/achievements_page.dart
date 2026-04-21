import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

/// Computes XP and badges from existing trackers' SharedPreferences data.
class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  int _tasbihTotal = 0;
  int _salahStreak = 0;
  int _salahTotalPrayers = 0;
  int _hifzAyahs = 0;
  int _fastingDays = 0;
  int _pagesRead = 0;
  int _quizHighScore = 0;
  int _quizRounds = 0;

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();

    // Tasbih
    final tasbihTotal = p.getInt('tasbih.total') ?? 0;

    // Salah
    int salahStreak = 0;
    int salahTotal = 0;
    final salahRaw = p.getString('salah.tracker.v1');
    if (salahRaw != null && salahRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(salahRaw) as Map<String, dynamic>;
        final dayKeys = decoded.keys.toList();
        for (final v in decoded.values) {
          if (v is List) salahTotal += v.length;
        }
        // Compute current streak
        DateTime d = DateTime.now();
        while (true) {
          final key =
              '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
          final arr = decoded[key];
          if (arr is List && arr.length >= 5) {
            salahStreak++;
            d = d.subtract(const Duration(days: 1));
          } else {
            break;
          }
        }
        dayKeys.length;
      } catch (_) {}
    }

    // Hifz
    int hifzAyahs = 0;
    final hifzRaw = p.getString('hifz.memorized.v1');
    if (hifzRaw != null && hifzRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(hifzRaw) as Map<String, dynamic>;
        for (final v in decoded.values) {
          if (v is num) hifzAyahs += v.toInt();
        }
      } catch (_) {}
    }

    // Fasting
    final fasts = p.getStringList('fasting.completed')?.length ?? 0;

    // Reading plan
    final pagesRead = p.getInt('reading_plan.pagesRead') ??
        p.getInt('reading_plan.v1.pagesRead') ??
        p.getInt('reading_plan.pages') ??
        0;

    // Quiz
    final quizHigh = p.getInt('quiz.highscore.v1') ?? 0;
    final quizRounds = p.getInt('quiz.played.v1') ?? 0;

    if (!mounted) return;
    setState(() {
      _tasbihTotal = tasbihTotal;
      _salahStreak = salahStreak;
      _salahTotalPrayers = salahTotal;
      _hifzAyahs = hifzAyahs;
      _fastingDays = fasts;
      _pagesRead = pagesRead;
      _quizHighScore = quizHigh;
      _quizRounds = quizRounds;
      _loaded = true;
    });
  }

  // XP formula: weighted combination of activities.
  int get _xp =>
      _tasbihTotal * 1 +
      _salahTotalPrayers * 20 +
      _salahStreak * 50 +
      _hifzAyahs * 30 +
      _fastingDays * 40 +
      _pagesRead * 10 +
      _quizHighScore * 25 +
      _quizRounds * 10;

  // Level: sqrt-based curve.
  int get _level {
    if (_xp <= 0) return 1;
    // L = floor(sqrt(XP/100)) + 1
    int l = 1;
    int need = 100;
    int total = 0;
    while (total + need <= _xp) {
      total += need;
      l++;
      need = (need * 1.35).round();
    }
    return l;
  }

  (int cur, int need) _levelProgress() {
    int need = 100;
    int total = 0;
    while (total + need <= _xp) {
      total += need;
      need = (need * 1.35).round();
    }
    final within = _xp - total;
    return (within, need);
  }

  List<_Badge> _computeBadges() {
    return [
      _Badge(
        title: 'Dhikr Devotee',
        description: 'Reach 1,000 tasbih total',
        icon: Icons.fingerprint_rounded,
        earned: _tasbihTotal >= 1000,
        progress: (_tasbihTotal / 1000).clamp(0, 1).toDouble(),
        progressLabel: '$_tasbihTotal / 1,000',
      ),
      _Badge(
        title: 'Dhikr Master',
        description: '10,000 tasbih total',
        icon: Icons.all_inclusive_rounded,
        earned: _tasbihTotal >= 10000,
        progress: (_tasbihTotal / 10000).clamp(0, 1).toDouble(),
        progressLabel: '$_tasbihTotal / 10,000',
      ),
      _Badge(
        title: 'Salah Keeper',
        description: '7-day prayer streak',
        icon: Icons.schedule_rounded,
        earned: _salahStreak >= 7,
        progress: (_salahStreak / 7).clamp(0, 1).toDouble(),
        progressLabel: '$_salahStreak / 7 days',
      ),
      _Badge(
        title: 'Salah Champion',
        description: '30-day prayer streak',
        icon: Icons.verified_rounded,
        earned: _salahStreak >= 30,
        progress: (_salahStreak / 30).clamp(0, 1).toDouble(),
        progressLabel: '$_salahStreak / 30 days',
      ),
      _Badge(
        title: 'Hāfiẓ in the making',
        description: 'Memorize 100 ayahs',
        icon: Icons.psychology_alt_rounded,
        earned: _hifzAyahs >= 100,
        progress: (_hifzAyahs / 100).clamp(0, 1).toDouble(),
        progressLabel: '$_hifzAyahs / 100 ayahs',
      ),
      _Badge(
        title: 'Juz 30 Memorized',
        description: 'Memorize 564 ayahs (approx. Juz 30)',
        icon: Icons.menu_book_rounded,
        earned: _hifzAyahs >= 564,
        progress: (_hifzAyahs / 564).clamp(0, 1).toDouble(),
        progressLabel: '$_hifzAyahs / 564 ayahs',
      ),
      _Badge(
        title: 'Ṣāʾim',
        description: 'Complete 10 fasts',
        icon: Icons.nightlight_round,
        earned: _fastingDays >= 10,
        progress: (_fastingDays / 10).clamp(0, 1).toDouble(),
        progressLabel: '$_fastingDays / 10 days',
      ),
      _Badge(
        title: 'Ramaḍān Companion',
        description: 'Complete 30 fasts',
        icon: Icons.mosque_rounded,
        earned: _fastingDays >= 30,
        progress: (_fastingDays / 30).clamp(0, 1).toDouble(),
        progressLabel: '$_fastingDays / 30 days',
      ),
      _Badge(
        title: 'Qāriʾ',
        description: 'Read 100 pages',
        icon: Icons.auto_stories_rounded,
        earned: _pagesRead >= 100,
        progress: (_pagesRead / 100).clamp(0, 1).toDouble(),
        progressLabel: '$_pagesRead / 100 pages',
      ),
      _Badge(
        title: 'Khatm Hero',
        description: 'Read all 604 pages',
        icon: Icons.emoji_events_rounded,
        earned: _pagesRead >= 604,
        progress: (_pagesRead / 604).clamp(0, 1).toDouble(),
        progressLabel: '$_pagesRead / 604 pages',
      ),
      _Badge(
        title: 'Seeker of Knowledge',
        description: 'Play 5 quiz rounds',
        icon: Icons.school_rounded,
        earned: _quizRounds >= 5,
        progress: (_quizRounds / 5).clamp(0, 1).toDouble(),
        progressLabel: '$_quizRounds / 5 rounds',
      ),
      _Badge(
        title: 'Quiz Ace',
        description: 'Score 10/10 in a round',
        icon: Icons.star_rounded,
        earned: _quizHighScore >= 10,
        progress: (_quizHighScore / 10).clamp(0, 1).toDouble(),
        progressLabel: '$_quizHighScore / 10 best',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 80;
    final badges = _computeBadges();
    final earnedCount = badges.where((b) => b.earned).length;
    final (cur, need) = _levelProgress();
    final pct = need == 0 ? 0.0 : cur / need;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      appBar: AppBar(
        title: const Text('Achievements'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loaded
                ? () {
                    setState(() => _loaded = false);
                    _load();
                  }
                : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.gold,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          children: [
            // Level card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.cardGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.gold25),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: AppColors.goldGradient,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: Text(
                            '$_level',
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 26,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Level',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _levelTitle(_level),
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_xp XP',
                              style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0, 1).toDouble(),
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceLightAlpha55,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.gold),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$cur / $need XP to next level',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Stats grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                _StatTile(
                    icon: Icons.fingerprint_rounded,
                    label: 'Tasbih',
                    value: _fmt(_tasbihTotal)),
                _StatTile(
                    icon: Icons.schedule_rounded,
                    label: 'Salah streak',
                    value: '$_salahStreak'),
                _StatTile(
                    icon: Icons.psychology_alt_rounded,
                    label: 'Hifz ayahs',
                    value: _fmt(_hifzAyahs)),
                _StatTile(
                    icon: Icons.nightlight_round,
                    label: 'Fasts',
                    value: '$_fastingDays'),
                _StatTile(
                    icon: Icons.auto_stories_rounded,
                    label: 'Pages read',
                    value: _fmt(_pagesRead)),
                _StatTile(
                    icon: Icons.school_rounded,
                    label: 'Quiz rounds',
                    value: '$_quizRounds'),
              ],
            ),

            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Badges',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '$earnedCount / ${badges.length}',
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final b in badges) ...[
              _BadgeTile(badge: b),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  static String _levelTitle(int l) {
    if (l >= 15) return 'Muḥsin';
    if (l >= 10) return 'Ṣābir';
    if (l >= 7) return 'Qāriʾ';
    if (l >= 4) return 'Sālik';
    if (l >= 2) return 'Mubtadiʾ';
    return 'Seeker';
  }
}

class _Badge {
  final String title;
  final String description;
  final IconData icon;
  final bool earned;
  final double progress;
  final String progressLabel;
  const _Badge({
    required this.title,
    required this.description,
    required this.icon,
    required this.earned,
    required this.progress,
    required this.progressLabel,
  });
}

class _BadgeTile extends StatelessWidget {
  final _Badge badge;
  const _BadgeTile({required this.badge});

  @override
  Widget build(BuildContext context) {
    final color = badge.earned ? AppColors.gold : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: badge.earned ? AppColors.gold25 : AppColors.dividerAlpha60),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: badge.earned ? AppColors.gold15 : AppColors.textMuted08,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: badge.earned
                      ? AppColors.gold30
                      : AppColors.dividerAlpha60),
            ),
            child: Icon(badge.icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        badge.title,
                        style: TextStyle(
                            color: badge.earned
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (badge.earned)
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.gold, size: 18),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  badge.description,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: badge.progress,
                    minHeight: 4,
                    backgroundColor: AppColors.surfaceLightAlpha55,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  badge.progressLabel,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: AppColors.gold, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
