import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/verse.dart';
import '../../../core/theme/app_theme.dart';
import '../../bookmarks/providers/bookmarks_provider.dart';
import '../../home/providers/home_provider.dart';
import '../providers/daily_ayah_provider.dart';

class DailyAyahPage extends ConsumerStatefulWidget {
  const DailyAyahPage({super.key});

  @override
  ConsumerState<DailyAyahPage> createState() => _DailyAyahPageState();
}

class _DailyAyahPageState extends ConsumerState<DailyAyahPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(dailyAyahProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dailyAyahProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),

                    // Streak badge
                    FadeInDown(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_fire_department, color: AppColors.gold, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '${state.streak} day streak',
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Title
                    FadeIn(
                      child: Text(
                        'Daily Ayah',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Verse card
                    if (state.verse != null)
                      FadeInUp(
                        delay: const Duration(milliseconds: 200),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.card,
                                AppColors.gold.withValues(alpha: 0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.gold.withValues(alpha: 0.15)),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.gold.withValues(alpha: 0.05),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Bismillah ornament
                              Icon(
                                Icons.star_rounded,
                                color: AppColors.gold.withValues(alpha: 0.4),
                                size: 24,
                              ),
                              const SizedBox(height: 20),

                              // Arabic text
                              Text(
                                state.verse!.arabicText ?? '',
                                style: const TextStyle(
                                  fontSize: 28,
                                  color: AppColors.gold,
                                  height: 2.2,
                                ),
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 24),
                              Divider(color: AppColors.gold.withValues(alpha: 0.15)),
                              const SizedBox(height: 16),

                              // Translation
                              Text(
                                state.verse!.translationText ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: AppColors.textSecondary,
                                  fontStyle: FontStyle.italic,
                                  height: 1.6,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 16),

                              // Verse key
                              Text(
                                state.verse!.verseKey,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.gold.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 32),

                    // Action buttons
                    if (state.verse != null)
                      FadeInUp(
                        delay: const Duration(milliseconds: 400),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _actionButton(
                              icon: Icons.share_outlined,
                              label: 'Share',
                              onTap: () => _shareVerse(state.verse!),
                            ),
                            const SizedBox(width: 16),
                            _actionButton(
                              icon: Icons.bookmark_outline,
                              label: 'Save',
                              onTap: () => _toggleBookmark(state.verse!),
                            ),
                            const SizedBox(width: 16),
                            _actionButton(
                              icon: Icons.auto_awesome_outlined,
                              label: 'Explain',
                              onTap: () => _explainVerse(state.verse!),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 40),

                    // Motivational text
                    FadeIn(
                      delay: const Duration(milliseconds: 600),
                      child: Text(
                        'Reflect on this verse today.\nCome back tomorrow for a new one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                          fontSize: 13,
                          height: 1.5,
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.gold, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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

  void _explainVerse(Verse verse) {
    final homeNotifier = ref.read(homeProvider.notifier);
    final prompt = 'Explain verse ${verse.verseKey}';
    context.go('/home');
    unawaited(homeNotifier.processTextInput(prompt));
  }
}
