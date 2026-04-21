import 'dart:async';

import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';

class IftarCountdownPage extends StatefulWidget {
  const IftarCountdownPage({super.key});

  @override
  State<IftarCountdownPage> createState() => _IftarCountdownPageState();
}

class _IftarCountdownPageState extends State<IftarCountdownPage> {
  PrayerTimes? _today;
  PrayerTimes? _tomorrow;
  Position? _pos;
  bool _loading = true;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (pos == null) {
      setState(() {
        _loading = false;
        _error = 'Location unavailable. Grant location permission to compute '
            'Fajr and Maghrib times.';
      });
      return;
    }
    final coords = Coordinates(pos.latitude, pos.longitude);
    final params = CalculationMethod.muslim_world_league.getParameters();
    final today = PrayerTimes.today(coords, params);
    final tomorrow = PrayerTimes(
      coords,
      DateComponents.from(DateTime.now().add(const Duration(days: 1))),
      params,
    );
    setState(() {
      _pos = pos;
      _today = today;
      _tomorrow = tomorrow;
      _loading = false;
    });
  }

  /// Whether we're currently fasting (between Fajr and Maghrib today).
  bool get _isFasting {
    final t = _today;
    if (t == null) return false;
    final now = DateTime.now();
    return now.isAfter(t.fajr) && now.isBefore(t.maghrib);
  }

  /// Next target: iftar (Maghrib) if fasting; else next Fajr (suhoor end).
  DateTime? get _target {
    final t = _today;
    final tm = _tomorrow;
    if (t == null) return null;
    final now = DateTime.now();
    if (_isFasting) return t.maghrib;
    // Before Fajr today -> Fajr today. After Maghrib -> Fajr tomorrow.
    if (now.isBefore(t.fajr)) return t.fajr;
    return tm?.fajr;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Iftar / Suhoor')),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold))
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_rounded,
                  color: AppColors.gold, size: 56),
              const SizedBox(height: 16),
              Text(_error ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );

  Widget _buildContent() {
    final t = _today!;
    final target = _target;
    final isFasting = _isFasting;
    final now = DateTime.now();
    final diff = target?.difference(now) ?? Duration.zero;

    final hh = diff.inHours.remainder(100).toString().padLeft(2, '0');
    final mm = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = diff.inSeconds.remainder(60).toString().padLeft(2, '0');

    final totalFastWindow = t.maghrib.difference(t.fajr).inSeconds;
    final elapsed = now.difference(t.fajr).inSeconds;
    final fastProgress = isFasting
        ? (elapsed / totalFastWindow).clamp(0.0, 1.0)
        : 0.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 80),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isFasting ? 'Time until Iftar' : 'Time until Suhoor / Fajr',
                  style: const TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text('$hh : $mm : $ss',
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
              const SizedBox(height: 12),
              if (isFasting)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: fastProgress,
                    minHeight: 8,
                    backgroundColor: Colors.white38,
                    color: Colors.black87,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                isFasting
                    ? '${(fastProgress * 100).toStringAsFixed(1)}% of fast complete'
                    : (target != null
                        ? 'Target: ${_fmtDateTime(target)}'
                        : ''),
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _row('Fajr (suhoor ends)', _fmt(t.fajr), Icons.wb_twilight_rounded),
        _row('Maghrib (iftar)', _fmt(t.maghrib), Icons.nights_stay_rounded),
        _row('Fasting window',
            '${t.maghrib.difference(t.fajr).inHours}h '
                '${t.maghrib.difference(t.fajr).inMinutes.remainder(60)}m',
            Icons.timelapse_rounded),
        const SizedBox(height: 12),
        if (_pos != null)
          Text(
            'Based on ${_pos!.latitude.toStringAsFixed(3)}, '
            '${_pos!.longitude.toStringAsFixed(3)}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Widget _row(String label, String value, IconData icon) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.gold, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
            ),
            Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  String _fmt(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  String _fmtDateTime(DateTime dt) {
    final isTomorrow = dt.day != DateTime.now().day;
    return '${isTomorrow ? "Tomorrow " : ""}${_fmt(dt)}';
  }
}
