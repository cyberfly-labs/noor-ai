import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:animate_do/animate_do.dart';
import 'package:intl/intl.dart';

import '../../../core/models/verse.dart';
import '../../../core/models/reading_goal.dart';
import '../../../core/theme/app_theme.dart';
import '../../bookmarks/providers/bookmarks_provider.dart';
import '../providers/daily_ayah_provider.dart';
import '../../reading_goals/providers/reading_goals_provider.dart';

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
      await ref.read(dailyAyahProvider.notifier).load(
            forceRefresh: widget.forceRefresh,
          );
      if (!mounted) {
        return;
      }
      await ref.read(readingGoalsProvider.notifier).load(silent: true);
    });
  }

  @override
  void didUpdateWidget(covariant DailyAyahPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldRefresh = widget.forceRefresh &&
        widget.refreshRequestId != null &&
        widget.refreshRequestId != oldWidget.refreshRequestId;

    if (shouldRefresh) {
      Future.microtask(() async {
        await ref.read(dailyAyahProvider.notifier).load(forceRefresh: true);
        if (!mounted) {
          return;
        }
        await ref.read(readingGoalsProvider.notifier).load(silent: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dailyAyahProvider);
    final goalsState = ref.watch(readingGoalsProvider);

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
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header row ─────────────────────────
                    Row(
                      children: [
                        Text(
                          'Daily Ayah',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const Spacer(),
                        FadeInDown(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.gold08,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.gold15),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_fire_department_rounded, color: AppColors.gold, size: 16),
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
                              Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.gold40),
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
                            Expanded(child: _actionButton(icon: Icons.copy_rounded, label: 'Copy', onTap: () => _shareVerse(state.verse!))),
                            const SizedBox(width: 10),
                            Expanded(child: _actionButton(icon: Icons.bookmark_outline_rounded, label: 'Save', onTap: () => _toggleBookmark(state.verse!))),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _actionButton(
                                icon: Icons.auto_awesome_outlined,
                                label: state.explanation != null ? 'Hide' : 'Explain',
                                onTap: () => ref.read(dailyAyahProvider.notifier).explainVerse(),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Explanation section ─────────────────
                    if (state.isExplaining || (state.explanation != null && state.explanation!.isNotEmpty))
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
                                  Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.gold),
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
                              if (state.explanation != null && state.explanation!.isNotEmpty)
                                MarkdownBody(
                                  data: state.explanation!,
                                  styleSheet: MarkdownStyleSheet(
                                    p: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.6),
                                    strong: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
                                    h1: const TextStyle(color: AppColors.gold, fontSize: 20),
                                    h2: const TextStyle(color: AppColors.gold, fontSize: 17),
                                    blockquoteDecoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: const Border(left: BorderSide(color: AppColors.gold, width: 3)),
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  'Generating explanation...',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                ),
                            ],
                          ),
                        ),
                      ),

                    if (goalsState.activeGoal != null || goalsState.isLoading)
                      FadeInUp(
                        child: _ReadingGoalProgressCard(
                          goal: goalsState.activeGoal,
                          progress: goalsState.todayProgress,
                          isLoading: goalsState.isLoading,
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
            Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _shareVerse(Verse verse) async {
    final shareText = '${verse.verseKey}\n\n${verse.arabicText ?? ''}\n\n${verse.translationText ?? ''}';
    await Clipboard.setData(ClipboardData(text: shareText));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verse copied to clipboard for sharing.')),
    );
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

class _ReadingGoalProgressCard extends StatelessWidget {
  const _ReadingGoalProgressCard({
    required this.goal,
    required this.progress,
    required this.isLoading,
  });

  final ReadingGoal? goal;
  final ReadingGoalProgress? progress;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading && goal == null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (goal == null) {
      return const SizedBox.shrink();
    }

    final activeGoal = goal!;
    final activeProgress = progress;
    final dueLabel = activeGoal.endDate == null
        ? null
        : DateFormat.yMMMd().format(activeGoal.endDate!.toLocal());

    return Container(
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
              Icon(Icons.flag_outlined, size: 16, color: AppColors.gold),
              const SizedBox(width: 8),
              const Text(
                'Reading Goal',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (dueLabel != null)
                Text(
                  'Due $dueLabel',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${activeGoal.target} ${activeGoal.goalTypeLabel}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            activeProgress?.summaryLabel ??
                'Your synced reading goal will update here as you progress.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (activeProgress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: activeProgress.progress,
                backgroundColor: AppColors.background,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.gold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${(activeProgress.progress * 100).round()}% complete',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  activeProgress.onTrack ? 'On track' : 'Keep going today',
                  style: TextStyle(
                    color: activeProgress.onTrack
                        ? AppColors.gold
                        : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
