import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/chapter_info.dart';
import '../../../core/models/surah.dart';
import '../../../core/models/verse.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/theme/app_theme.dart';

class SurahDetailPage extends StatefulWidget {
  const SurahDetailPage({
    super.key,
    required this.surahNumber,
  });

  final int surahNumber;

  @override
  State<SurahDetailPage> createState() => _SurahDetailPageState();
}

class _SurahDetailPageState extends State<SurahDetailPage> {
  late final Future<_SurahDetailData> _detailFuture;
  bool _isInfoExpanded = false;
  bool _isPlayingSurah = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: FutureBuilder<_SurahDetailData>(
          future: _detailFuture,
          builder: (context, snapshot) {
            final surah = snapshot.data?.surah;
            if (surah == null) {
              return Text('Surah ${widget.surahNumber}');
            }

            return Text(surah.englishName);
          },
        ),
      ),
      body: FutureBuilder<_SurahDetailData>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            );
          }

          final detail = snapshot.data;
          if (detail == null || detail.verses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'I could not load this surah right now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ),
            );
          }

          final headerItems = detail.chapterInfo == null ? 1 : 2;

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            itemCount: detail.verses.length + headerItems,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildHeader(context, detail);
              }

              if (detail.chapterInfo != null && index == 1) {
                return _buildChapterInfoCard(context, detail.chapterInfo!);
              }

              final verseIndex = index - headerItems;
              final verse = detail.verses[verseIndex];
              return _buildVerseCard(context, verse);
            },
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, _SurahDetailData detail) {
    final surah = detail.surah;
    final title = surah?.englishName ?? 'Surah ${widget.surahNumber}';
    final subtitle = surah?.englishNameTranslation ?? '';
    final arabicName = surah?.name ?? '';
    final meta = surah == null
        ? '${detail.verses.length} ayahs'
        : '${surah.numberOfAyahs} ayahs • ${_formatRevelationType(surah.revelationType)}';
    final pageRange = _pageRangeLabel(surah);
    final hasAudio = detail.verses.any((verse) => (verse.audioUrl ?? '').trim().isNotEmpty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.card,
            AppColors.surfaceLight,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.88),
                fontSize: 14,
              ),
            ),
          ],
          if (arabicName.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                arabicName,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetaChip(meta),
              if (pageRange.isNotEmpty) _buildMetaChip(pageRange),
              _buildMetaChip('Tap any ayah for tafsir'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: hasAudio ? () => _toggleSurahPlayback(detail) : null,
                  icon: Icon(
                    _isPlayingSurah ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                  ),
                  label: Text(_isPlayingSurah ? 'Stop Audio' : 'Listen Through'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: detail.verses.isEmpty
                      ? null
                      : () => context.push('/verse/${widget.surahNumber}/1'),
                  icon: const Icon(Icons.auto_stories_rounded),
                  label: const Text('Start Reading'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: BorderSide(color: AppColors.gold.withValues(alpha: 0.28)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChapterInfoCard(BuildContext context, ChapterInfo info) {
    final fullText = info.text.trim().isNotEmpty ? info.text.trim() : info.shortText.trim();
    final shortText = info.shortText.trim().isNotEmpty ? info.shortText.trim() : fullText;
    final canExpand = fullText.isNotEmpty && fullText != shortText;
    final visibleText = _isInfoExpanded ? fullText : shortText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'About This Surah',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          if (info.source.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildMetaChip(info.source.trim()),
          ],
          if (visibleText.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              visibleText,
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.94),
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
          if (canExpand) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _isInfoExpanded = !_isInfoExpanded;
                });
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.gold,
                padding: EdgeInsets.zero,
              ),
              child: Text(_isInfoExpanded ? 'Show less' : 'Read more'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerseCard(BuildContext context, Verse verse) {
    final hasAudio = (verse.audioUrl ?? '').trim().isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/verse/${verse.surahNumber}/${verse.ayahNumber}'),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold.withValues(alpha: 0.12),
                  ),
                  child: Text(
                    '${verse.ayahNumber}',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                if (hasAudio)
                  IconButton(
                    onPressed: () => _playVerseAudio(verse),
                    icon: const Icon(
                      Icons.play_circle_fill_rounded,
                      color: AppColors.gold,
                    ),
                    tooltip: 'Play ayah',
                    splashRadius: 20,
                  ),
                Text(
                  verse.verseKey,
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if ((verse.arabicText ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  verse.arabicText!,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 24,
                    height: 1.9,
                  ),
                ),
              ),
            ],
            if ((verse.translationText ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                verse.translationText!,
                style: TextStyle(
                  color: AppColors.textPrimary.withValues(alpha: 0.95),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<_SurahDetailData> _loadDetail() async {
    final surahFuture = QuranApiService.instance.listSurahs().then(
      (surahs) {
        for (final surah in surahs) {
          if (surah.number == widget.surahNumber) {
            return surah;
          }
        }
        return null;
      },
    );
    final chapterInfoFuture = QuranApiService.instance.getChapterInfo(widget.surahNumber);
    final versesFuture = QuranApiService.instance.getSurahVerses(widget.surahNumber);

    final results = await Future.wait<dynamic>([
      surahFuture,
      chapterInfoFuture,
      versesFuture,
    ]);

    return _SurahDetailData(
      surah: results[0] as Surah?,
      chapterInfo: results[1] as ChapterInfo?,
      verses: results[2] as List<Verse>,
    );
  }

  String _pageRangeLabel(Surah? surah) {
    final pages = surah?.pages ?? const <int>[];
    if (pages.isEmpty) {
      return '';
    }

    final first = pages.first;
    final last = pages.last;
    return first == last ? 'Page $first' : 'Pages $first-$last';
  }

  String _formatRevelationType(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Unknown revelation';
    }

    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }

  Widget _buildMetaChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textSecondary.withValues(alpha: 0.9),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _toggleSurahPlayback(_SurahDetailData detail) async {
    if (_isPlayingSurah) {
      await VoiceService.instance.stopPlayback();
      if (!mounted) {
        return;
      }

      setState(() {
        _isPlayingSurah = false;
      });
      return;
    }

    final urls = detail.verses
        .map((verse) => verse.audioUrl?.trim() ?? '')
        .where((url) => url.isNotEmpty)
        .toList(growable: false);

    if (urls.isEmpty) {
      _showMessage('Audio is not available for this surah right now.');
      return;
    }

    setState(() {
      _isPlayingSurah = true;
    });

    try {
      await VoiceService.instance.playUrls(urls);
    } catch (_) {
      _showMessage('I could not start surah playback right now.');
    } finally {
      if (mounted) {
        setState(() {
          _isPlayingSurah = false;
        });
      }
    }
  }

  Future<void> _playVerseAudio(Verse verse) async {
    final url = verse.audioUrl?.trim() ?? '';
    if (url.isEmpty) {
      _showMessage('Audio is not available for ${verse.verseKey}.');
      return;
    }

    try {
      await VoiceService.instance.playUrl(url);
    } catch (_) {
      _showMessage('I could not play ${verse.verseKey} right now.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SurahDetailData {
  const _SurahDetailData({
    required this.surah,
    required this.chapterInfo,
    required this.verses,
  });

  final Surah? surah;
  final ChapterInfo? chapterInfo;
  final List<Verse> verses;
}