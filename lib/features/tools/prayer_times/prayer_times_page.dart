import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';

class PrayerTimesPage extends StatefulWidget {
  const PrayerTimesPage({super.key});

  @override
  State<PrayerTimesPage> createState() => _PrayerTimesPageState();
}

class _PrayerTimesPageState extends State<PrayerTimesPage> {
  PrayerTimes? _times;
  SunnahTimes? _sunnah;
  Position? _position;
  String? _error;
  bool _loading = true;

  CalculationMethod _method = CalculationMethod.muslim_world_league;
  Madhab _madhab = Madhab.shafi;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (pos == null) {
      setState(() {
        _loading = false;
        _error = 'Location unavailable. Grant location permission to compute '
            'prayer times.';
      });
      return;
    }

    final coords = Coordinates(pos.latitude, pos.longitude);
    final params = _method.getParameters()..madhab = _madhab;
    final times = PrayerTimes.today(coords, params);

    setState(() {
      _position = pos;
      _times = times;
      _sunnah = SunnahTimes(times);
      _loading = false;
    });
  }

  String _fmt(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Prayer Times')),
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
    final t = _times!;
    final now = DateTime.now();
    final entries = <(String, DateTime, IconData)>[
      ('Fajr', t.fajr, Icons.brightness_4_rounded),
      ('Sunrise', t.sunrise, Icons.wb_twilight_rounded),
      ('Dhuhr', t.dhuhr, Icons.wb_sunny_rounded),
      ('Asr', t.asr, Icons.wb_cloudy_rounded),
      ('Maghrib', t.maghrib, Icons.nights_stay_rounded),
      ('Isha', t.isha, Icons.bedtime_rounded),
    ];

    // Determine next prayer.
    final upcoming = entries.where((e) => e.$2.isAfter(now)).toList();
    final next = upcoming.isNotEmpty ? upcoming.first : entries.first;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 80,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Next prayer',
                  style: TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(next.$1,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 28,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(_fmt(next.$2),
                  style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...entries.map((e) => _row(e.$1, _fmt(e.$2), e.$3,
            isNext: e.$1 == next.$1)),
        const SizedBox(height: 16),
        if (_sunnah != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Sunnah times',
                style: TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w700)),
          ),
          _row('Middle of the night', _fmt(_sunnah!.middleOfTheNight),
              Icons.dark_mode_rounded),
          _row('Last third of the night', _fmt(_sunnah!.lastThirdOfTheNight),
              Icons.auto_awesome_rounded),
        ],
        const SizedBox(height: 16),
        _buildSettings(),
        if (_position != null) ...[
          const SizedBox(height: 12),
          Text(
            'Based on ${_position!.latitude.toStringAsFixed(3)}, '
            '${_position!.longitude.toStringAsFixed(3)}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String time, IconData icon,
      {bool isNext = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isNext ? AppColors.gold10 : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isNext ? AppColors.gold30 : AppColors.divider, width: 0.8),
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
          Text(time,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Calculation',
              style: TextStyle(
                  color: AppColors.gold, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          DropdownButton<CalculationMethod>(
            value: _method,
            isExpanded: true,
            dropdownColor: AppColors.surfaceLight,
            items: const [
              DropdownMenuItem(
                  value: CalculationMethod.muslim_world_league,
                  child: Text('Muslim World League')),
              DropdownMenuItem(
                  value: CalculationMethod.egyptian,
                  child: Text('Egyptian')),
              DropdownMenuItem(
                  value: CalculationMethod.karachi, child: Text('Karachi')),
              DropdownMenuItem(
                  value: CalculationMethod.umm_al_qura,
                  child: Text('Umm Al-Qura')),
              DropdownMenuItem(
                  value: CalculationMethod.dubai, child: Text('Dubai')),
              DropdownMenuItem(
                  value: CalculationMethod.moon_sighting_committee,
                  child: Text('Moonsighting Committee')),
              DropdownMenuItem(
                  value: CalculationMethod.north_america,
                  child: Text('ISNA (North America)')),
              DropdownMenuItem(
                  value: CalculationMethod.kuwait, child: Text('Kuwait')),
              DropdownMenuItem(
                  value: CalculationMethod.qatar, child: Text('Qatar')),
              DropdownMenuItem(
                  value: CalculationMethod.singapore, child: Text('Singapore')),
              DropdownMenuItem(
                  value: CalculationMethod.turkey, child: Text('Turkey')),
              DropdownMenuItem(
                  value: CalculationMethod.tehran, child: Text('Tehran')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _method = v);
              _recompute();
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Madhab:',
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('Shafi'),
                selected: _madhab == Madhab.shafi,
                onSelected: (_) {
                  setState(() => _madhab = Madhab.shafi);
                  _recompute();
                },
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Hanafi'),
                selected: _madhab == Madhab.hanafi,
                onSelected: (_) {
                  setState(() => _madhab = Madhab.hanafi);
                  _recompute();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _recompute() {
    final pos = _position;
    if (pos == null) return;
    final coords = Coordinates(pos.latitude, pos.longitude);
    final params = _method.getParameters()..madhab = _madhab;
    final times = PrayerTimes.today(coords, params);
    setState(() {
      _times = times;
      _sunnah = SunnahTimes(times);
    });
  }
}
