import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

class TasbihPage extends StatefulWidget {
  const TasbihPage({super.key});

  @override
  State<TasbihPage> createState() => _TasbihPageState();
}

class _TasbihPageState extends State<TasbihPage>
    with SingleTickerProviderStateMixin {
  static const List<({String arabic, String transliteration})> _dhikrs = [
    (arabic: 'سُبْحَانَ اللّٰهِ', transliteration: 'SubhanAllah'),
    (arabic: 'الْحَمْدُ لِلّٰهِ', transliteration: 'Alhamdulillah'),
    (arabic: 'اللّٰهُ أَكْبَرُ', transliteration: 'Allahu Akbar'),
    (arabic: 'لَا إِلٰهَ إِلَّا اللّٰهُ', transliteration: 'La ilaha illa Allah'),
    (arabic: 'أَسْتَغْفِرُ اللّٰهَ', transliteration: 'Astaghfirullah'),
    (arabic: 'لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللّٰهِ', transliteration: 'La hawla wa la quwwata illa billah'),
  ];
  static const List<int> _targets = [33, 99, 100, 500];

  int _count = 0;
  int _total = 0;
  int _dhikrIndex = 0;
  int _target = 33;
  bool _hapticsOn = true;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _loadPrefs();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _prefs = p;
      _count = p.getInt('tasbih.count') ?? 0;
      _total = p.getInt('tasbih.total') ?? 0;
      _dhikrIndex = p.getInt('tasbih.dhikrIndex') ?? 0;
      _target = p.getInt('tasbih.target') ?? 33;
      _hapticsOn = p.getBool('tasbih.haptics') ?? true;
    });
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt('tasbih.count', _count);
    await p.setInt('tasbih.total', _total);
    await p.setInt('tasbih.dhikrIndex', _dhikrIndex);
    await p.setInt('tasbih.target', _target);
    await p.setBool('tasbih.haptics', _hapticsOn);
  }

  void _increment() {
    setState(() {
      _count++;
      _total++;
    });
    _pulseController.forward().then((_) => _pulseController.reverse());
    if (_hapticsOn) HapticFeedback.lightImpact();
    if (_count % _target == 0 && _hapticsOn) {
      HapticFeedback.mediumImpact();
    }
    _save();
  }

  void _reset() {
    setState(() => _count = 0);
    if (_hapticsOn) HapticFeedback.selectionClick();
    _save();
  }

  void _resetAll() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Reset All',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'This will reset both the current count and total.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _count = 0;
                _total = 0;
              });
              _save();
              Navigator.pop(ctx);
            },
            child: const Text(
              'Reset',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_count % _target) / _target;
    final cycle = _count ~/ _target;
    final dhikr = _dhikrs[_dhikrIndex.clamp(0, _dhikrs.length - 1)];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tasbih'),
        actions: [
          IconButton(
            tooltip: _hapticsOn ? 'Haptics on' : 'Haptics off',
            onPressed: () {
              setState(() => _hapticsOn = !_hapticsOn);
              _save();
            },
            icon: Icon(
              _hapticsOn
                  ? Icons.vibration_rounded
                  : Icons.do_not_disturb_on_outlined,
              color: _hapticsOn ? AppColors.gold : AppColors.textMuted,
            ),
          ),
          IconButton(
            tooltip: 'Reset all',
            onPressed: _resetAll,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Dhikr selector ─────────────────────────
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _dhikrs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final selected = i == _dhikrIndex;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _dhikrIndex = i);
                      _save();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.gold12
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: selected
                              ? AppColors.gold30
                              : AppColors.divider,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        _dhikrs[i].transliteration,
                        style: TextStyle(
                          color: selected
                              ? AppColors.gold
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Target selector ─────────────────────────
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'Target:',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ..._targets.map((t) {
                    final sel = _target == t;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _target = t);
                          _save();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.gold12
                                : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel
                                  ? AppColors.gold25
                                  : AppColors.divider,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            '$t',
                            style: TextStyle(
                              color: sel
                                  ? AppColors.gold
                                  : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: sel
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

            // ── Main counter ────────────────────────────
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: _increment,
                  behavior: HitTestBehavior.opaque,
                  child: ScaleTransition(
                    scale: _pulseAnim,
                    child: SizedBox(
                      width: 280,
                      height: 280,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Progress ring
                          SizedBox(
                            width: 280,
                            height: 280,
                            child: CustomPaint(
                              painter: _RingPainter(progress: progress),
                            ),
                          ),
                          // Inner circle
                          Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.cardHighlight,
                                  AppColors.card,
                                ],
                              ),
                              border: Border.all(
                                color: AppColors.gold20,
                                width: 0.8,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dhikr.arabic,
                                  style: const TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 18,
                                    height: 1.6,
                                  ),
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.rtl,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$_count',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 60,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  cycle > 0
                                      ? 'Cycle $cycle · Total $_total'
                                      : 'Total $_total',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Tap the circle to count',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),

            // ── Bottom actions ──────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                MediaQuery.of(context).padding.bottom + 80,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Reset'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(
                          color: AppColors.divider,
                          width: 0.8,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _increment,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: AppColors.goldGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 20,
                              color: Colors.black,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Count',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  const _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const strokeWidth = 10.0;

    // Background ring
    final bgPaint = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = const LinearGradient(
          colors: [AppColors.goldDark, AppColors.gold, AppColors.goldLight],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
