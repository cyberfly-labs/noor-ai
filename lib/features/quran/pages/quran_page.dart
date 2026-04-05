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
  List<Surah> _allSurahs = const <Surah>[];
  List<Surah> _matchingSurahs = const <Surah>[];
  bool _responseCardDismissed = false;

  static const List<({String label, String prompt})> _featuredPrompts = [
    (label: 'Hope & mercy', prompt: 'Show me Quran verses about hope and mercy.'),
    (label: 'Patience', prompt: 'Show me Quran verses about patience.'),
    (label: 'Surah Al-Kahf', prompt: 'Explain the themes of Surah Al-Kahf.'),
    (label: 'Gratitude', prompt: 'Show me Quran verses about gratitude.'),
    (label: 'Forgiveness', prompt: 'Show me Quran verses about forgiveness.'),
  ];

  static const List<int> _featuredSurahNumbers = [1, 18, 36, 55, 67, 112];

  @override
  void initState() {
    super.initState();
    _surahsFuture = _loadSurahs();
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
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Centered title row
                  Row(
                    children: [
                      const SizedBox(width: 48), // balance spacer
                      const Spacer(),
                      Text(
                        'Quran',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              fontSize: 22,
                            ),
                      ),
                      const Spacer(),
                      if (!keyboardOpen)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold08,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '114 Surahs',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Composer-style question input ──────
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: TextField(
                      controller: _questionController,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ask from the whole Quran...',
                        hintStyle: TextStyle(
                          color: AppColors.textMuted80,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 8),
                          child: Icon(
                            Icons.auto_awesome_outlined,
                            size: 20,
                            color: AppColors.gold60,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_hasQuestionInput)
                              IconButton(
                                onPressed: () => _questionController.clear(),
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: AppColors.textMuted,
                                ),
                                tooltip: 'Clear',
                              ),
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: _hasQuestionInput
                                      ? AppColors.goldGradient
                                      : null,
                                  color: _hasQuestionInput
                                      ? null
                                      : Colors.transparent,
                                ),
                                child: IconButton(
                                  onPressed: _hasQuestionInput
                                      ? () => _sendQuestion(
                                            _questionController.text,
                                          )
                                      : null,
                                  icon: Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18,
                                    color: _hasQuestionInput
                                        ? AppColors.background
                                        : AppColors.textMuted.withValues(
                                            alpha: 0.3,
                                          ),
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 14,
                        ),
                      ),
                      onSubmitted: _sendQuestion,
                    ),
                  ),

                  if (!keyboardOpen &&
                      !_responseCardDismissed &&
                      homeState.response != null &&
                      homeState.response!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildResponseCard(homeState),
                  ],

                  const SizedBox(height: 10),

                  // ── Search input ───────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _handleSearchChanged,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search surahs or keywords...',
                        hintStyle: TextStyle(
                          color: AppColors.textMuted80,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 8),
                          child: const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: AppColors.textMuted,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                        suffixIcon: _activeSearchQuery.isEmpty
                            ? null
                            : IconButton(
                                onPressed: _clearSearch,
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: AppColors.textMuted,
                                ),
                                tooltip: 'Clear search',
                              ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),

                  if (!keyboardOpen && _activeSearchQuery.isEmpty) ...[
                    const SizedBox(height: 16),
                    _buildBrowseHighlights(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

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

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(context).padding.bottom + 80,
          ),
          itemCount: surahs.length,
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
        final hasSurahMatches = _matchingSurahs.isNotEmpty;
        if (!hasSurahMatches && results.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 40,
                  color: AppColors.textMuted40,
                ),
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

        return ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(context).padding.bottom + 80,
          ),
          children: [
            if (hasSurahMatches) ...[
              _SearchSectionHeader(
                title: 'Matching surahs',
                countLabel: '${_matchingSurahs.length}',
              ),
              const SizedBox(height: 10),
              ..._matchingSurahs.map(
                (surah) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SurahTile(
                    surah: surah,
                    onTap: () => _openSurahDetail(surah),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (results.isNotEmpty) ...[
              _SearchSectionHeader(
                title: 'Matching verses',
                countLabel: '${results.length}',
              ),
              const SizedBox(height: 10),
              ...results.map(
                (verse) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _VerseResultTile(
                    verse: verse,
                    onTap: () => _openVerseDetail(verse.verseKey),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBrowseHighlights() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Popular prompts — pill chips
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            'POPULAR PROMPTS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _featuredPrompts
              .map(
                (item) => GestureDetector(
                  onTap: () {
                    _questionController.text = item.prompt;
                    _sendQuestion(item.prompt);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      '"${item.label}"',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 20),

        // Quick jump — horizontal scroll cards
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            'QUICK JUMP',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _featuredSurahNumbers.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final surahNumber = _featuredSurahNumbers[index];
              Surah? surah;
              for (final item in _allSurahs) {
                if (item.number == surahNumber) {
                  surah = item;
                  break;
                }
              }
              if (surah == null) {
                return const SizedBox.shrink();
              }

              return GestureDetector(
                onTap: () => _openSurahDetail(surah!),
                child: Container(
                  width: 120,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.gold10,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${surah.number}',
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            surah.name,
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        surah.englishName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),
        // All surahs label
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            'ALL SURAHS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: AppColors.gold,
                ),
                const SizedBox(width: 6),
                Text(
                  'Latest answer',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _responseCardDismissed = true),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            MarkdownBody(
              data: state.response ?? '',
              styleSheet: AppTheme.markdownCompactStyle,
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold08,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.gold12,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                citation.quranSourceLabel,
                                style: TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tafsir: ${citation.tafsirSourceLabel}',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
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
        _matchingSurahs = const <Surah>[];
        _searchResultsFuture = null;
      });
      return;
    }

    setState(() {
      _activeSearchQuery = trimmed;
      _matchingSurahs = _filterSurahs(trimmed);
    });

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _searchResultsFuture = _quranRag.searchVerses(trimmed);
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _activeSearchQuery = '';
      _matchingSurahs = const <Surah>[];
      _searchResultsFuture = null;
    });
  }

  void _sendQuestion(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    _responseCardDismissed = false;
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

  Future<List<Surah>> _loadSurahs() async {
    final surahs = await QuranApiService.instance.listSurahs();
    if (mounted) {
      setState(() {
        _allSurahs = surahs;
      });
    } else {
      _allSurahs = surahs;
    }
    return surahs;
  }

  List<Surah> _filterSurahs(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const <Surah>[];
    }

    final matches = _allSurahs
        .where((surah) {
          return surah.number.toString() == normalized ||
              surah.englishName.toLowerCase().contains(normalized) ||
              surah.englishNameTranslation.toLowerCase().contains(normalized) ||
              surah.name.contains(query);
        })
        .toList(growable: false);

    return matches.take(6).toList(growable: false);
  }
}

class _SearchSectionHeader extends StatelessWidget {
  const _SearchSectionHeader({required this.title, required this.countLabel});

  final String title;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.gold08,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            countLabel,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Compact surah list tile ──────────────────────────────────────────────

class _SurahTile extends StatelessWidget {
  final Surah surah;
  final VoidCallback onTap;

  const _SurahTile({required this.surah, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Number badge
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${surah.number}',
                style: const TextStyle(
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
                  const SizedBox(height: 3),
                  Text(
                    '${surah.englishNameTranslation} · ${surah.numberOfAyahs} ayahs',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
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
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textMuted40,
            ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold10,
                    borderRadius: BorderRadius.circular(20),
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
                  'Surah ${verse.surahNumber} · Ayah ${verse.ayahNumber}',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
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
