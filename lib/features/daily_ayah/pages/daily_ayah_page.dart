import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:animate_do/animate_do.dart';

import '../../../core/models/verse.dart';
import '../../../core/services/verse_share_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../bookmarks/providers/bookmarks_provider.dart';
import '../providers/daily_ayah_provider.dart';

class DailyAyahPage extends ConsumerStatefulWidget {
  const DailyAyahPage({
    super.key,
    this.autoExplain = false,
    this.forceRefresh = false,
    this.refreshRequestId,
    this.requestedVerseKey,
  });

  final bool autoExplain;
  final bool forceRefresh;
  final String? refreshRequestId;
  final String? requestedVerseKey;

  @override
  ConsumerState<DailyAyahPage> createState() => _DailyAyahPageState();
}

class _DailyAyahPageState extends ConsumerState<DailyAyahPage> {
  bool _didAutoExplain = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref
          .read(dailyAyahProvider.notifier)
          .load(forceRefresh: widget.forceRefresh);
    });
  }

  @override
  void didUpdateWidget(covariant DailyAyahPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldRefresh =
        widget.forceRefresh &&
        widget.refreshRequestId != null &&
        widget.refreshRequestId != oldWidget.refreshRequestId;

    if (shouldRefresh) {
      Future.microtask(() async {
        await ref.read(dailyAyahProvider.notifier).load(forceRefresh: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dailyAyahProvider);

    if (widget.autoExplain && !_didAutoExplain && state.verse != null) {
      _didAutoExplain = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref.read(dailyAyahProvider.notifier).explainVerse();
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: state.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              )
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(context).padding.bottom + 80,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header row ─────────────────────────
                    Row(
                      children: [
                        Text(
                          'Daily Ayah',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const Spacer(),
                        FadeInDown(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold08,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.gold15),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  color: AppColors.gold,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${state.streak} day${state.streak == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Verse card ─────────────────────────
                    if (state.verse != null)
                      FadeInUp(
                        delay: const Duration(milliseconds: 150),
                        duration: const Duration(milliseconds: 400),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            children: [
                              // Ornament
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 20,
                                color: AppColors.gold40,
                              ),
                              const SizedBox(height: 20),

                              // Arabic text
                              Text(
                                state.verse!.arabicText ?? '',
                                style: const TextStyle(
                                  fontSize: 26,
                                  color: AppColors.gold,
                                  height: 2.0,
                                ),
                                textDirection: ui.TextDirection.rtl,
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 20),
                              Container(height: 0.5, color: AppColors.divider),
                              const SizedBox(height: 16),

                              // Translation
                              Text(
                                state.verse!.translationText ?? '',
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: AppColors.textSecondary,
                                  fontStyle: FontStyle.italic,
                                  height: 1.6,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 16),

                              // Verse key pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.gold10,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  state.verse!.verseKey,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // ── Action buttons ─────────────────────
                    if (state.verse != null)
                      FadeInUp(
                        delay: const Duration(milliseconds: 300),
                        duration: const Duration(milliseconds: 400),
                        child: Row(
                          children: [
                            Expanded(
                              child: _actionButton(
                                icon: Icons.copy_rounded,
                                label: 'Copy',
                                onTap: () => _shareVerse(state.verse!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _actionButton(
                                icon: Icons.bookmark_outline_rounded,
                                label: 'Save',
                                onTap: () => _toggleBookmark(state.verse!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _actionButton(
                                icon: Icons.auto_awesome_outlined,
                                label: state.explanation != null
                                    ? 'Hide'
                                    : 'Explain',
                                onTap: () => ref
                                    .read(dailyAyahProvider.notifier)
                                    .explainVerse(),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Explanation section ─────────────────
                    if (state.isExplaining ||
                        (state.explanation != null &&
                            state.explanation!.isNotEmpty))
                      FadeInUp(
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 16),
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
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 16,
                                    color: AppColors.gold,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Explanation',
                                    style: TextStyle(
                                      color: AppColors.gold,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (state.isExplaining)
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.gold60,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (state.explanation != null &&
                                  state.explanation!.isNotEmpty)
                                MarkdownBody(
                                  data: state.explanation!,
                                  styleSheet: MarkdownStyleSheet(
                                    p: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      height: 1.6,
                                    ),
                                    strong: const TextStyle(
                                      color: AppColors.gold,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    h1: const TextStyle(
                                      color: AppColors.gold,
                                      fontSize: 20,
                                    ),
                                    h2: const TextStyle(
                                      color: AppColors.gold,
                                      fontSize: 17,
                                    ),
                                    blockquoteDecoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: const Border(
                                        left: BorderSide(
                                          color: AppColors.gold,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  'Generating explanation...',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 32),

                    // Motivational text
                    FadeIn(
                      delay: const Duration(milliseconds: 500),
                      child: Center(
                        child: Text(
                          'Reflect on this verse today.\nCome back tomorrow for a new one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textMuted60,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.gold, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareVerse(Verse verse) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.dividerAlpha60,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.image_rounded, color: AppColors.gold),
              title: const Text('Share as image',
                  style: TextStyle(color: AppColors.textPrimary)),
              subtitle: const Text('Generate a styled verse card',
                  style: TextStyle(color: AppColors.textMuted)),
              onTap: () => Navigator.of(ctx).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_rounded,
                  color: AppColors.gold),
              title: const Text('Share as text',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(ctx).pop('text'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: AppColors.gold),
              title: const Text('Copy to clipboard',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(ctx).pop('copy'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final arabic = verse.arabicText ?? '';
    final translation = verse.translationText;
    final reference = verse.verseKey;
    if (choice == 'image') {
      await VerseShareService.shareAsImage(
        arabic: arabic,
        translation: translation,
        reference: reference,
      );
    } else if (choice == 'text') {
      await VerseShareService.shareAsText(
        arabic: arabic,
        translation: translation,
        reference: reference,
      );
    } else {
      final shareText =
          '$reference\n\n$arabic\n\n${translation ?? ''}';
      await Clipboard.setData(ClipboardData(text: shareText));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verse copied to clipboard.')),
      );
    }
  }

  Future<void> _toggleBookmark(Verse verse) async {
    final added = await ref.read(bookmarksProvider.notifier).toggleVerse(verse);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? 'Saved verse ${verse.verseKey}.'
              : 'Removed verse ${verse.verseKey}.',
        ),
      ),
    );
  }
}
