import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/surah.dart';
import '../../../core/models/verse.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../home/providers/home_provider.dart';

class QuranPage extends ConsumerStatefulWidget {
  const QuranPage({super.key});

  @override
  ConsumerState<QuranPage> createState() => _QuranPageState();
}

class _QuranPageState extends ConsumerState<QuranPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _questionController = TextEditingController();
  late final Future<List<Surah>> _surahsFuture;
  Future<List<Verse>>? _searchResultsFuture;
  Timer? _searchDebounce;
  String _activeSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _surahsFuture = QuranApiService.instance.listSurahs();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final homeState = ref.watch(homeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quran',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppColors.gold,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Browse surahs and ask questions with global Quran answers.',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.card,
                          AppColors.gold.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildHeaderStat(
                            label: 'Surahs',
                            value: '114',
                          ),
                        ),
                        Expanded(
                          child: _buildHeaderStat(
                            label: 'Browse',
                            value: 'By name, page, or number',
                            alignEnd: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _questionController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Ask from the whole Quran...',
                      hintStyle: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      suffixIcon: IconButton(
                        onPressed: () => _sendQuestion(_questionController.text),
                        icon: const Icon(Icons.send_rounded, color: AppColors.gold),
                      ),
                    ),
                    onSubmitted: _sendQuestion,
                  ),
                  if (homeState.response != null && homeState.response!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildResponseCard(homeState),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: _handleSearchChanged,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search keywords across the Quran...',
                      hintStyle: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _activeSearchQuery.isEmpty
                  ? FutureBuilder<List<Surah>>(
                      future: _surahsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: AppColors.gold),
                          );
                        }

                        final surahs = snapshot.data ?? const <Surah>[];
                        if (surahs.isEmpty) {
                          return Center(
                            child: Text(
                              'Could not load the surah list.',
                              style: TextStyle(
                                color: AppColors.textSecondary.withValues(alpha: 0.8),
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemCount: surahs.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final surah = surahs[index];
                            final pageRange = _formatPageRange(surah.pages);

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => _openSurahDetail(surah),
                                child: Ink(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.surface,
                                        AppColors.card.withValues(alpha: 0.92),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: AppColors.gold.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 46,
                                            height: 46,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: AppColors.gold.withValues(alpha: 0.12),
                                              border: Border.all(
                                                color: AppColors.gold.withValues(alpha: 0.16),
                                              ),
                                            ),
                                            child: Text(
                                              '${surah.number}',
                                              style: const TextStyle(
                                                color: AppColors.gold,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  surah.englishName,
                                                  style: const TextStyle(
                                                    color: AppColors.textPrimary,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  surah.englishNameTranslation,
                                                  style: TextStyle(
                                                    color: AppColors.textSecondary.withValues(alpha: 0.86),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: AppColors.textSecondary.withValues(alpha: 0.8),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        surah.name,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _buildMetaChip(
                                            icon: Icons.menu_book_rounded,
                                            label: '${surah.numberOfAyahs} ayahs',
                                          ),
                                          _buildMetaChip(
                                            icon: Icons.auto_stories_rounded,
                                            label: _formatRevelationType(surah.revelationType),
                                          ),
                                          if (pageRange != null)
                                            _buildMetaChip(
                                              icon: Icons.bookmark_outline_rounded,
                                              label: pageRange,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Open surah details, read every ayah, and start playback from one place.',
                                        style: TextStyle(
                                          color: AppColors.textSecondary.withValues(alpha: 0.8),
                                          fontSize: 12,
                                          height: 1.45,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Text(
                                            'Open Surah',
                                            style: TextStyle(
                                              color: AppColors.goldLight,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.north_east_rounded,
                                            size: 16,
                                            color: AppColors.goldLight,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    )
                  : FutureBuilder<List<Verse>>(
                      future: _searchResultsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: AppColors.gold),
                          );
                        }

                        final results = snapshot.data ?? const <Verse>[];
                        if (results.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                'No Quran verses matched "$_activeSearchQuery".',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemCount: results.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final verse = results[index];

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => _openVerseDetail(verse.verseKey),
                                child: Ink(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: AppColors.gold.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.gold.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              verse.verseKey,
                                              style: const TextStyle(
                                                color: AppColors.gold,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          Icon(
                                            Icons.north_east_rounded,
                                            size: 18,
                                            color: AppColors.goldLight,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Surah ${verse.surahNumber} • Ayah ${verse.ayahNumber}',
                                        style: TextStyle(
                                          color: AppColors.textSecondary.withValues(alpha: 0.85),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        verse.translationText?.trim().isNotEmpty == true
                                            ? verse.translationText!.trim()
                                            : 'Open this verse to read full details.',
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 14,
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderStat({
    required String label,
    required String value,
    bool alignEnd = false,
  }) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: AppColors.goldLight.withValues(alpha: 0.88),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: alignEnd ? 13 : 24,
            fontWeight: alignEnd ? FontWeight.w500 : FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildMetaChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.goldLight),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseCard(HomeState state) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 240),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.14)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latest answer',
              style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            MarkdownBody(
              data: state.response ?? '',
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.5,
                ),
                strong: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (state.citations.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: state.citations
                    .map(
                      (citation) => ActionChip(
                        onPressed: () => _openVerseDetail(citation.verseKey),
                        backgroundColor: AppColors.card,
                        side: BorderSide(color: AppColors.gold.withValues(alpha: 0.16)),
                        label: Text(
                          citation.verseKey,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRevelationType(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Revelation unknown';
    }

    return '${trimmed[0].toUpperCase()}${trimmed.substring(1).toLowerCase()} surah';
  }

  String? _formatPageRange(List<int> pages) {
    if (pages.isEmpty) {
      return null;
    }

    final first = pages.first;
    final last = pages.last;
    if (first == last) {
      return 'Page $first';
    }

    return 'Pages $first-$last';
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _activeSearchQuery = '';
        _searchResultsFuture = null;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _activeSearchQuery = trimmed;
        _searchResultsFuture = QuranApiService.instance.search(trimmed);
      });
    });
  }

  void _sendQuestion(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    _questionController.clear();
    ref.read(homeProvider.notifier).processTextInput(trimmed);
  }

  void _openVerseDetail(String verseKey) {
    final parts = verseKey.split(':');
    if (parts.length != 2) {
      return;
    }

    final surahNumber = int.tryParse(parts[0]);
    final ayahNumber = int.tryParse(parts[1]);
    if (surahNumber == null || ayahNumber == null) {
      return;
    }

    context.push('/verse/$surahNumber/$ayahNumber');
  }

  void _openSurahDetail(Surah surah) {
    context.push('/quran/surah/${surah.number}');
  }
}
