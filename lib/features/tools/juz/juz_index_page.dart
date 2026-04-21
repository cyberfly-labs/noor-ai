import 'package:flutter/material.dart';

import '../../../core/models/juz_info.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/theme/app_theme.dart';

/// Lists all 30 Juzs (Paras) with their surah/ayah ranges.
class JuzIndexPage extends StatefulWidget {
  const JuzIndexPage({super.key});

  @override
  State<JuzIndexPage> createState() => _JuzIndexPageState();
}

class _JuzIndexPageState extends State<JuzIndexPage> {
  List<JuzInfo>? _juzs;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await QuranApiService.instance.listJuzs();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (data.isEmpty) {
        _error = 'Unable to load Juz index. Check your connection or Quran '
            'Foundation API configuration.';
      } else {
        _juzs = data;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Juz Index')),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold))
            : _error != null
                ? _buildError()
                : _buildList(),
      ),
    );
  }

  Widget _buildError() => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: AppColors.gold, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  Widget _buildList() {
    final juzs = _juzs!;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 80),
      itemCount: juzs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _JuzTile(juz: juzs[i]),
    );
  }
}

class _JuzTile extends StatelessWidget {
  final JuzInfo juz;
  const _JuzTile({required this.juz});

  String _rangeLabel() {
    if (juz.verseMapping.isEmpty) {
      return '${juz.versesCount} ayahs';
    }
    final entries = juz.verseMapping.entries.toList()
      ..sort((a, b) =>
          int.parse(a.key).compareTo(int.parse(b.key)));
    final first = entries.first;
    final last = entries.last;
    final firstAyah = first.value.split('-').first;
    final lastAyah = last.value.split('-').last;
    return '${first.key}:$firstAyah → ${last.key}:$lastAyah';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold15),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.gold10,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold30),
            ),
            child: Text('${juz.juzNumber}',
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Juz ${juz.juzNumber}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                const SizedBox(height: 2),
                Text(_rangeLabel(),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 2),
                Text('${juz.versesCount} ayahs',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          if (juz.verseMapping.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.list_alt_rounded, color: AppColors.gold),
              tooltip: 'Surah mapping',
              onPressed: () => _showMapping(context),
            ),
        ],
      ),
    );
  }

  void _showMapping(BuildContext context) {
    final entries = juz.verseMapping.entries.toList()
      ..sort((a, b) =>
          int.parse(a.key).compareTo(int.parse(b.key)));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Juz ${juz.juzNumber} • Surah mapping',
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
              const SizedBox(height: 12),
              ...entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.gold10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(e.key,
                              style: const TextStyle(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 12),
                        Text('Surah ${e.key}',
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('ayahs ${e.value}',
                            style: const TextStyle(
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
