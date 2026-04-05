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
            if (surah == null) return Text('Surah ${widget.surahNumber}');
            return Text(surah.englishName);
          },
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      body: FutureBuilder<_SurahDetailData>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
          }

          final detail = snapshot.data;
          if (detail == null || detail.verses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load this surah right now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            );
          }

          final headerItems = detail.chapterInfo == null ? 1 : 2;

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            itemCount: detail.verses.length + headerItems,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) return _buildHeader(context, detail);
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
    final hasAudio = detail.verses.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
          if (arabicName.isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                arabicName,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: AppColors.gold, fontSize: 26, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildMetaChip(meta),
              if (pageRange.isNotEmpty) _buildMetaChip(pageRange),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: hasAudio ? () => _toggleSurahPlayback(detail) : null,
                  icon: Icon(_isPlayingSurah ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
                  label: Text(_isPlayingSurah ? 'Stop' : 'Listen', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: detail.verses.isEmpty
                      ? null
                      : () => context.push('/verse/${widget.surahNumber}/1'),
                  icon: const Icon(Icons.auto_stories_rounded, size: 18),
                  label: const Text('Read', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: BorderSide(color: AppColors.gold25),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.gold),
              const SizedBox(width: 10),
              Text(
                'About This Surah',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
              ),
            ],
          ),
          if (info.source.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildMetaChip(info.source.trim()),
          ],
          if (visibleText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              visibleText,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.6),
            ),
          ],
          if (canExpand) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _isInfoExpanded = !_isInfoExpanded),
              style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: EdgeInsets.zero),
              child: Text(_isInfoExpanded ? 'Show less' : 'Read more', style: const TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerseCard(BuildContext context, Verse verse) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/verse/${verse.surahNumber}/${verse.ayahNumber}'),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    '${verse.ayahNumber}',
                    style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _playVerseAudio(verse),
                  icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.gold, size: 24),
                  tooltip: 'Play ayah',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const SizedBox(width: 4),
                Text(
                  verse.verseKey,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
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
                  style: const TextStyle(color: AppColors.gold, fontSize: 22, height: 1.9),
                ),
              ),
            ],
            if ((verse.translationText ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                verse.translationText!,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.6),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.gold08,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
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

    var urls = detail.verses
        .map((verse) => verse.audioUrl?.trim() ?? '')
        .where((url) => url.isNotEmpty)
        .toList(growable: false);

    if (urls.isEmpty) {
      urls = await QuranApiService.instance.getSurahAudioUrls(widget.surahNumber);
    }

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
    var url = verse.audioUrl?.trim() ?? '';
    if (url.isEmpty) {
      url = (await QuranApiService.instance.getAudioUrl(
        verse.surahNumber,
        verse.ayahNumber,
      ))?.trim() ?? '';
    }

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