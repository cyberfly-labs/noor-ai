import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/chapter_info.dart';
import '../../../core/models/surah.dart';
import '../../../core/models/verse.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/services/quran_user_sync_service.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/theme/app_theme.dart';

class SurahDetailPage extends StatefulWidget {
  const SurahDetailPage({super.key, required this.surahNumber});

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
    // Record reading session when user opens a surah
    _recordReadingSession();
  }

  Future<void> _recordReadingSession() async {
    try {
      final firstVerse = Verse(
        verseKey: '${widget.surahNumber}:1',
        surahNumber: widget.surahNumber,
        ayahNumber: 1,
      );
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await QuranUserSyncService.instance.updateReadingSession(firstVerse);
      await QuranUserSyncService.instance.recordActivityForVerse(
        firstVerse,
        date: today,
        seconds: 120,
      );
    } catch (_) {
      // Non-critical — silently skip if not signed in
    }
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
        : '${surah.numberOfAyahs} ayahs · ${_formatRevelationType(surah.revelationType)}';
    final pageRange = _pageRangeLabel(surah);
    final hasAudio = detail.verses.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.cardHighlight,
            AppColors.card,
            AppColors.gold04,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold20, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (arabicName.isNotEmpty)
                Text(
                  arabicName,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
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
                child: GestureDetector(
                  onTap: hasAudio ? () => _toggleSurahPlayback(detail) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      gradient: hasAudio ? AppColors.goldGradient : null,
                      color: hasAudio ? null : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isPlayingSurah
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          size: 20,
                          color: hasAudio ? Colors.black : AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isPlayingSurah ? 'Stop' : 'Listen',
                          style: TextStyle(
                            color: hasAudio ? Colors.black : AppColors.textMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: detail.verses.isEmpty
                      ? null
                      : () => context.push('/verse/${widget.surahNumber}/1'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: AppColors.gold10,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.gold25, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_stories_rounded,
                          size: 18,
                          color: AppColors.gold,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Read',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
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
    final fullText = info.text.trim().isNotEmpty
        ? info.text.trim()
        : info.shortText.trim();
    final shortText = info.shortText.trim().isNotEmpty
        ? info.shortText.trim()
        : fullText;
    final canExpand = fullText.isNotEmpty && fullText != shortText;
    final visibleText = _isInfoExpanded ? fullText : shortText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.gold08,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'About This Surah',
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
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
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.65,
              ),
            ),
          ],
          if (canExpand) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () =>
                  setState(() => _isInfoExpanded = !_isInfoExpanded),
              child: Text(
                _isInfoExpanded ? 'Show less' : 'Read more',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerseCard(BuildContext context, Verse verse) {
    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            context.push('/verse/${verse.surahNumber}/${verse.ayahNumber}'),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.gold08,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.gold15),
                    ),
                    child: Text(
                      '${verse.ayahNumber}',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _playVerseAudio(verse),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.gold08,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: AppColors.gold,
                        size: 18,
                      ),
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
                      fontSize: 22,
                      height: 1.9,
                    ),
                  ),
                ),
              ],
              if ((verse.translationText ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  verse.translationText!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<_SurahDetailData> _loadDetail() async {
    final surahFuture = QuranApiService.instance.listSurahs().then((surahs) {
      for (final surah in surahs) {
        if (surah.number == widget.surahNumber) {
          return surah;
        }
      }
      return null;
    });
    final chapterInfoFuture = QuranApiService.instance.getChapterInfo(
      widget.surahNumber,
    );
    final versesFuture = QuranApiService.instance.getSurahVerses(
      widget.surahNumber,
    );

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
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
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

    final urls = await QuranApiService.instance.getSurahAudioUrls(
      widget.surahNumber,
      verses: detail.verses,
    );

    if (urls.isEmpty) {
      _showMessage('Audio is not available for this surah right now.');
      return;
    }

    if (urls.length < detail.verses.length) {
      _showMessage(
        'Some ayahs are missing audio. Playing the available verses in order.',
      );
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
      url =
          (await QuranApiService.instance.getAudioUrl(
            verse.surahNumber,
            verse.ayahNumber,
          ))?.trim() ??
          '';
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
