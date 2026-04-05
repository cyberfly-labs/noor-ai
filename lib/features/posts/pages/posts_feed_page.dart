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

class _PostsFeedPageState extends State<PostsFeedPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // My Reflections state
  List<QFPost> _myPosts = [];
  bool _isLoadingMy = true;
  String? _myError;
  String? _deletingId;

  // Community feed state
  List<QFPost> _communityPosts = [];
  bool _isLoadingCommunity = true;
  String? _communityError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCommunity();
    _loadMy();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadCommunity() async {
    setState(() {
      _isLoadingCommunity = true;
      _communityError = null;
    });
    try {
      final posts =
          await QuranUserSyncService.instance.fetchCommunityFeed(limit: 30);
      if (mounted) {
        setState(() {
          _communityPosts = posts;
          _isLoadingCommunity = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingCommunity = false;
          _communityError = 'Could not load community reflections.';
        });
      }
    }
  }

  Future<void> _loadMy() async {
    if (!QuranUserSessionService.instance.isSignedIn) {
      if (mounted) setState(() => _isLoadingMy = false);
      return;
    }
    setState(() {
      _isLoadingMy = true;
      _myError = null;
    });
    try {
      final posts =
          await QuranUserSyncService.instance.listPosts(limit: 50);
      if (mounted) {
        setState(() {
          _myPosts = posts;
          _isLoadingMy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMy = false;
          _myError = 'Could not load your reflections.';
        });
      }
    }
  }

  Future<void> _delete(QFPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete reflection?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This will permanently remove the reflection from QuranReflect.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
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
        _myPosts.removeWhere((p) => p.id == post.id);
        _deletingId = null;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Reflection deleted')));
    } else {
      setState(() => _deletingId = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Could not delete. Try again.')));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Reflections',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      onPressed: () {
                        if (_tabController.index == 0) {
                          _loadCommunity();
                        } else {
                          _loadMy();
                        }
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      color: AppColors.textMuted,
                      padding: EdgeInsets.zero,
                      tooltip: 'Refresh',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Tab bar ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.gold,
                labelColor: AppColors.gold,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(text: 'Community'),
                  Tab(text: 'My Reflections'),
                ],
              ),
            ),

            // ── Tab views ────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCommunityTab(bottomPadding),
                  _buildMyTab(bottomPadding),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Community tab ──────────────────────────────────────────────────────────

  Widget _buildCommunityTab(double bottomPadding) {
    if (_isLoadingCommunity) {
      return const Center(
        child: CircularProgressIndicator(
            color: AppColors.gold, strokeWidth: 2),
      );
    }
    if (_communityError != null) {
      return _buildErrorView(_communityError!, _loadCommunity);
    }
    if (_communityPosts.isEmpty) {
      return _buildEmptyView(
        icon: Icons.forum_outlined,
        title: 'No reflections yet',
        subtitle:
            'Community reflections from QuranReflect will appear here.',
      );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.surface,
      onRefresh: _loadCommunity,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding + 88),
        itemCount: _communityPosts.length,
        separatorBuilder: (_, itemIndex) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _CommunityPostCard(
          post: _communityPosts[i],
        ),
      ),
    );
  }

  // ── My Reflections tab ─────────────────────────────────────────────────────

  Widget _buildMyTab(double bottomPadding) {
    final isSignedIn = QuranUserSessionService.instance.isSignedIn;
    if (!isSignedIn) return _buildSignInPrompt();
    if (_isLoadingMy) {
      return const Center(
        child: CircularProgressIndicator(
            color: AppColors.gold, strokeWidth: 2),
      );
    }
    if (_myError != null) {
      return _buildErrorView(_myError!, _loadMy);
    }
    if (_myPosts.isEmpty) {
      return _buildEmptyView(
        icon: Icons.article_outlined,
        title: 'No reflections yet',
        subtitle:
            'Ask Noor a question and share the response — it will appear here.',
      );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.surface,
      onRefresh: _loadMy,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding + 88),
        itemCount: _myPosts.length,
        separatorBuilder: (_, itemIndex) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _MyPostCard(
          post: _myPosts[i],
          isDeleting: _deletingId == _myPosts[i].id,
          onDelete: () => _delete(_myPosts[i]),
        ),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _buildErrorView(String message, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 14)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
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
              child: Icon(icon, size: 32, color: AppColors.gold),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.5),
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
              child: const Icon(Icons.lock_outline_rounded,
                  size: 32, color: AppColors.gold),
            ),
            const SizedBox(height: 20),
            Text(
              'Sign in to see your reflections',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect your Quran Foundation account to share reflections on QuranReflect.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Go to Settings'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Community post card ──────────────────────────────────────────────────────

class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({required this.post});

  final QFPost post;

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('MMM d, yyyy').format(post.createdAt.toLocal());

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
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold10,
                ),
                child: const Icon(Icons.person_outline_rounded,
                    size: 14, color: AppColors.gold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  post.author ?? 'Community member',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                dateStr,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
          if (post.verseRanges.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: post.verseRanges
                  .map((r) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.gold10,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.gold20),
                        ),
                        child: Text(
                          r,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.gold,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          _quranReflectBadge(),
        ],
      ),
    );
  }
}

// ── My post card ─────────────────────────────────────────────────────────────

class _MyPostCard extends StatelessWidget {
  const _MyPostCard({
    required this.post,
    required this.isDeleting,
    required this.onDelete,
  });

  final QFPost post;
  final bool isDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy • h:mm a')
        .format(post.createdAt.toLocal());

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
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold10,
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 13, color: AppColors.gold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dateStr,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ),
              if (isDeleting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.error),
                )
              else
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 16),
                    color: AppColors.textMuted,
                    padding: EdgeInsets.zero,
                    tooltip: 'Delete',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          _quranReflectBadge(),
        ],
      ),
    );
  }
}

// ── Shared badge ─────────────────────────────────────────────────────────────

Widget _quranReflectBadge() {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.gold08,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gold18),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.share_rounded, size: 10, color: AppColors.gold),
            SizedBox(width: 4),
            Text(
              'QuranReflect',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
