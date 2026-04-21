import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import 'surah_meta.dart';

/// Track how many ayahs of each surah have been memorized.
class HifzTrackerPage extends StatefulWidget {
  const HifzTrackerPage({super.key});

  @override
  State<HifzTrackerPage> createState() => _HifzTrackerPageState();
}

class _HifzTrackerPageState extends State<HifzTrackerPage> {
  static const _key = 'hifz.memorized.v1';

  SharedPreferences? _prefs;
  // surah index (0-based) -> ayahs memorized.
  Map<int, int> _memorized = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    final m = <int, int>{};
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) => m[int.parse(k)] = (v as num).toInt());
      } catch (_) {}
    }
    setState(() {
      _prefs = p;
      _memorized = m;
    });
  }

  Future<void> _save() async {
    await _prefs?.setString(
        _key,
        jsonEncode(_memorized.map((k, v) => MapEntry(k.toString(), v))));
  }

  int get _totalMemorized {
    int n = 0;
    _memorized.forEach((_, v) => n += v);
    return n;
  }

  int get _surahsComplete {
    int n = 0;
    for (int i = 0; i < surahsMeta.length; i++) {
      if ((_memorized[i] ?? 0) >= surahsMeta[i].$2) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalMemorized / totalAyahs;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Hifz Tracker')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.of(context).padding.bottom + 80),
          children: [
            _overview(progress),
            const SizedBox(height: 16),
            const Text('Surahs',
                style: TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...List.generate(surahsMeta.length, (i) => _surahTile(i)),
          ],
        ),
      ),
    );
  }

  Widget _overview(double progress) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Memorized',
              style: TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('$_totalMemorized / $totalAyahs ayahs',
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white24,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).toStringAsFixed(1)}% of Quran • '
            '$_surahsComplete / ${surahsMeta.length} surahs complete',
            style: const TextStyle(
                color: Colors.black87, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _surahTile(int index) {
    final (name, count) = surahsMeta[index];
    final current = _memorized[index] ?? 0;
    final ratio = current / count;
    final done = current >= count;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: done ? AppColors.success : AppColors.divider, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.gold10,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.gold20),
            ),
            child: Text('${index + 1}',
                style: const TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 4,
                    backgroundColor: AppColors.divider,
                    color: done ? AppColors.success : AppColors.gold,
                  ),
                ),
                const SizedBox(height: 2),
                Text('$current / $count ayahs',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            onPressed: current > 0
                ? () {
                    setState(() => _memorized[index] = current - 1);
                    _save();
                  }
                : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
            color: AppColors.textMuted,
          ),
          IconButton(
            onPressed: current < count
                ? () {
                    setState(() => _memorized[index] = current + 1);
                    _save();
                  }
                : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: AppColors.gold,
          ),
          IconButton(
            onPressed: () {
              setState(() => _memorized[index] = count);
              _save();
            },
            icon: const Icon(Icons.done_all_rounded),
            color: AppColors.success,
            tooltip: 'Mark complete',
          ),
        ],
      ),
    );
  }
}
