import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/services/quran_user_session_service.dart';
import '../../../core/services/quran_user_sync_service.dart';
import '../../../core/theme/app_theme.dart';

class PostsFeedPage extends StatefulWidget {
  const PostsFeedPage({super.key});

  @override
  State<PostsFeedPage> createState() => _PostsFeedPageState();
}

class _PostsFeedPageState extends State<PostsFeedPage> {
  List<QFPost> _posts = [];
  bool _isLoading = true;
  String? _error;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!QuranUserSessionService.instance.isSignedIn) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final posts = await QuranUserSyncService.instance.listPosts(limit: 50);
      if (mounted) setState(() { _posts = posts; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _error = 'Could not load posts.'; });
    }
  }

  Future<void> _delete(QFPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete post?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This will permanently remove the post from QuranReflect.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingId = post.id);
    final ok = await QuranUserSyncService.instance.deletePost(post.id);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _posts.removeWhere((p) => p.id == post.id);
        _deletingId = null;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Post deleted')));
    } else {
      setState(() => _deletingId = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not delete post. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isSignedIn = QuranUserSessionService.instance.isSignedIn;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
              child: Row(
                children: [
                  Text(
                    'My Posts',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const Spacer(),
                  if (isSignedIn && _posts.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.gold08,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.gold15),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.article_outlined, size: 14, color: AppColors.gold),
                          const SizedBox(width: 4),
                          Text(
                            '${_posts.length}',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isSignedIn) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        onPressed: _isLoading ? null : _load,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        color: AppColors.textMuted,
                        padding: EdgeInsets.zero,
                        tooltip: 'Refresh',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ── Subtitle ────────────────────────────────────────────
            if (isSignedIn)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Text(
                  'Shared with QuranReflect',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),

            const SizedBox(height: 14),

            // ── Content ─────────────────────────────────────────────
            Expanded(
              child: _buildBody(bottomPadding, isSignedIn),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(double bottomPadding, bool isSignedIn) {
    if (!isSignedIn) return _buildSignInPrompt();
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_posts.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding + 88),
        itemCount: _posts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _PostCard(
          post: _posts[i],
          isDeleting: _deletingId == _posts[i].id,
          onDelete: () => _delete(_posts[i]),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold06,
                border: Border.all(color: AppColors.gold15),
              ),
              child: const Icon(Icons.article_outlined, size: 32, color: AppColors.gold),
            ),
            const SizedBox(height: 20),
            Text(
              'No posts yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask Noor a question and share the response to QuranReflect — it will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold06,
                border: Border.all(color: AppColors.gold15),
              ),
              child: const Icon(Icons.lock_outline_rounded, size: 32, color: AppColors.gold),
            ),
            const SizedBox(height: 20),
            Text(
              'Sign in to see posts',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect your Quran Foundation account to view and share posts on QuranReflect.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Go to Settings'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Post card ──────────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.isDeleting,
    required this.onDelete,
  });

  final QFPost post;
  final bool isDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(post.createdAt.toLocal());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: icon + date + delete ──────────────────────────
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold10,
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 13, color: AppColors.gold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dateStr,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ),
              if (isDeleting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
                )
              else
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    color: AppColors.textMuted,
                    padding: EdgeInsets.zero,
                    tooltip: 'Delete',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Body ───────────────────────────────────────────────────
          Text(
            post.body,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              height: 1.55,
            ),
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
          ),

          // ── QuranReflect badge ─────────────────────────────────────
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold08,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.gold18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.share_rounded, size: 10, color: AppColors.gold),
                    const SizedBox(width: 4),
                    Text(
                      'QuranReflect',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
