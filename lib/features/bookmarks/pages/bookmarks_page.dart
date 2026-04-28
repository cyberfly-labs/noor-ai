import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/bookmarks_provider.dart';

class BookmarksPage extends ConsumerStatefulWidget {
  const BookmarksPage({super.key});

  @override
  ConsumerState<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends ConsumerState<BookmarksPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(bookmarksProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookmarksProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Text(
                    'Saved',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const Spacer(),
                  if (state.bookmarks.isNotEmpty)
                    Container(
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
                            Icons.bookmark_rounded,
                            size: 14,
                            color: AppColors.gold,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${state.bookmarks.length}',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Content ──────────────────────────────────
            Expanded(
              child: state.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    )
                  : state.bookmarks.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        bottomPadding + 80,
                      ),
                      itemCount: state.bookmarks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final bookmark = state.bookmarks[index];
                        return FadeInUp(
                          delay: Duration(milliseconds: index * 35),
                          duration: const Duration(milliseconds: 280),
                          child: _BookmarkCard(
                            bookmark: bookmark,
                            onDelete: () => ref
                                .read(bookmarksProvider.notifier)
                                .remove(bookmark.verseKey),
                            onTap: () {
                              final parts = bookmark.verseKey.split(':');
                              if (parts.length == 2) {
                                final s = int.tryParse(parts[0]);
                                final a = int.tryParse(parts[1]);
                                if (s != null && a != null) {
                                  context.push('/verse/$s/$a');
                                }
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceLight,
              border: Border.all(color: AppColors.divider),
            ),
            child: const Icon(
              Icons.bookmark_outline_rounded,
              size: 36,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No saved verses yet',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bookmark verses while reading to find them here',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final dynamic bookmark;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _BookmarkCard({
    required this.bookmark,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.gold20),
                  ),
                  child: Text(
                    bookmark.verseKey,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                    ),
                    color: AppColors.textMuted,
                    padding: EdgeInsets.zero,
                    onPressed: onDelete,
                  ),
                ),
              ],
            ),
            if (bookmark.arabicText != null &&
                bookmark.arabicText!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                bookmark.arabicText!,
                style: const TextStyle(
                  fontSize: 20,
                  color: AppColors.gold,
                  height: 1.9,
                ),
                textDirection: TextDirection.rtl,
              ),
            ],
            if (bookmark.translationText != null &&
                bookmark.translationText!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                bookmark.translationText!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
              ),
            ],
            if (bookmark.note != null && bookmark.note!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.notes_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bookmark.note!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
