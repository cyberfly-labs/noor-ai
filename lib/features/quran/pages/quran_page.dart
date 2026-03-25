import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/surah.dart';
import '../../../core/models/verse.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/services/quran_rag_service.dart';
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
  bool _hasQuestionInput = false;
  late final Future<List<Surah>> _surahsFuture;
  Future<List<Verse>>? _searchResultsFuture;
  Timer? _searchDebounce;
  String _activeSearchQuery = '';
  final QuranRagService _quranRag = QuranRagService.instance;

  @override
  void initState() {
    super.initState();
    _surahsFuture = QuranApiService.instance.listSurahs();
    _questionController.addListener(() {
      final hasInput = _questionController.text.trim().isNotEmpty;
      if (hasInput != _hasQuestionInput) {
        setState(() => _hasQuestionInput = hasInput);
      }
    });
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
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header area ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Quran',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                      ),
                      const Spacer(),
                      if (!keyboardOpen)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.gold.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            '114 Surahs',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Question input ─────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: TextField(
                      controller: _questionController,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Ask from the whole Quran...',
                        hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.8)),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        prefixIcon: Icon(Icons.auto_awesome_outlined, size: 20, color: AppColors.gold.withValues(alpha: 0.5)),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_hasQuestionInput)
                              IconButton(
                                onPressed: () => _questionController.clear(),
                                icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                                tooltip: 'Clear',
                              ),
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _hasQuestionInput ? AppColors.gold : Colors.transparent,
                                ),
                                child: IconButton(
                                  onPressed: _hasQuestionInput
                                      ? () => _sendQuestion(_questionController.text)
                                      : null,
                                  icon: Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 18,
                                    color: _hasQuestionInput
                                        ? AppColors.background
                                        : AppColors.textMuted.withValues(alpha: 0.4),
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onSubmitted: _sendQuestion,
                    ),
                  ),

                  if (!keyboardOpen && homeState.response != null && homeState.response!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildResponseCard(homeState),
                  ],

                  const SizedBox(height: 12),

                  // ── Search input ───────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _handleSearchChanged,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search surahs or keywords...',
                        hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.8)),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Surah list / Search results ──────────────
            if (!keyboardOpen)
              Expanded(
                child: _activeSearchQuery.isEmpty
                    ? _buildSurahList()
                    : _buildSearchResults(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSurahList() {
    return FutureBuilder<List<Surah>>(
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
              style: TextStyle(color: AppColors.textMuted),
            ),
          );
        }

        return ListView.separated(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 80),
          itemCount: surahs.length,
          separatorBuilder: (_, __) => Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: AppColors.divider.withValues(alpha: 0.5),
          ),
          itemBuilder: (context, index) {
            final surah = surahs[index];
            return _SurahTile(
              surah: surah,
              onTap: () => _openSurahDetail(surah),
            );
          },
        );
      },
    );
  }

  Widget _buildSearchResults() {
    return FutureBuilder<List<Verse>>(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off_rounded, size: 40, color: AppColors.textMuted.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text(
                  'No results for "$_activeSearchQuery"',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 80),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final verse = results[index];
            return _VerseResultTile(
              verse: verse,
              onTap: () => _openVerseDetail(verse.verseKey),
            );
          },
        );
      },
    );
  }

  Widget _buildResponseCard(HomeState state) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.gold),
                const SizedBox(width: 6),
                Text(
                  'Latest answer',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            MarkdownBody(
              data: state.response ?? '',
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
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
                spacing: 6,
                runSpacing: 6,
                children: state.citations
                    .map(
                      (citation) => GestureDetector(
                        onTap: () => _openVerseDetail(citation.verseKey),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.gold.withValues(alpha: 0.12)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                citation.quranSourceLabel,
                                style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tafsir: ${citation.tafsirSourceLabel}',
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
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
        _searchResultsFuture = _quranRag.searchVerses(trimmed);
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

// ── Compact surah list tile ──────────────────────────────────────────────

class _SurahTile extends StatelessWidget {
  final Surah surah;
  final VoidCallback onTap;

  const _SurahTile({required this.surah, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            // Number badge
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                '${surah.number}',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Title area
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    surah.englishName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${surah.englishNameTranslation} • ${surah.numberOfAyahs} ayahs',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Arabic name
            Text(
              surah.name,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textMuted.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ── Verse search result tile ─────────────────────────────────────────────

class _VerseResultTile extends StatelessWidget {
  final Verse verse;
  final VoidCallback onTap;

  const _VerseResultTile({required this.verse, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    verse.verseKey,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Surah ${verse.surahNumber} • Ayah ${verse.ayahNumber}',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              verse.translationText?.trim().isNotEmpty == true
                  ? verse.translationText!.trim()
                  : 'Open to read full details.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
