import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/reflection_post.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/theme/app_theme.dart';

/// Feed of community reflections and lessons from Quran Reflect.
class ReflectionsFeedPage extends StatefulWidget {
  const ReflectionsFeedPage({super.key});

  @override
  State<ReflectionsFeedPage> createState() => _ReflectionsFeedPageState();
}

class _ReflectionsFeedPageState extends State<ReflectionsFeedPage> {
  final List<ReflectionPost> _posts = [];
  final ScrollController _scroll = ScrollController();

  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
              _scroll.position.maxScrollExtent - 300 &&
          !_loading &&
          _hasMore) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final batch =
        await QuranApiService.instance.fetchReflectionsFeed(page: _page);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (batch.isEmpty) {
        if (_posts.isEmpty) {
          _error = 'No reflections found. Ensure Quran Foundation API is '
              'configured, then retry.';
        }
        _hasMore = false;
      } else {
        _posts.addAll(batch);
        _page++;
        if (batch.length < 20) _hasMore = false;
      }
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _posts.clear();
      _page = 1;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reflections')),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.gold,
          onRefresh: _refresh,
          child: _posts.isEmpty && _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.gold))
              : _posts.isEmpty && _error != null
                  ? _buildError()
                  : _buildList(),
        ),
      ),
    );
  }

  Widget _buildError() => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.menu_book_rounded,
              color: AppColors.gold, size: 56),
          const SizedBox(height: 12),
          Text(_error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: _refresh,
              child: const Text('Retry'),
            ),
          ),
        ],
      );

  Widget _buildList() {
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 80),
      itemCount: _posts.length + (_hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _posts.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.gold)),
          );
        }
        return _ReflectionCard(post: _posts[i]);
      },
    );
  }
}

class _ReflectionCard extends StatelessWidget {
  final ReflectionPost post;
  const _ReflectionCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.gold10,
                backgroundImage: post.authorAvatarUrl != null
                    ? NetworkImage(post.authorAvatarUrl!)
                    : null,
                child: post.authorAvatarUrl == null
                    ? const Icon(Icons.person_outline,
                        color: AppColors.gold, size: 18)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.authorName ?? 'Anonymous',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700)),
                    if (post.authorUsername != null)
                      Text('@${post.authorUsername}',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              if (post.kind != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold10,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.gold20),
                  ),
                  child: Text(post.kind!.toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          if (post.verseKeys.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: post.verseKeys
                  .take(6)
                  .map((k) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Text(k,
                            style: const TextStyle(
                                color: AppColors.gold,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ))
                  .toList(),
            ),
          ],
          if (post.title != null) ...[
            const SizedBox(height: 10),
            Text(post.title!,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ],
          const SizedBox(height: 8),
          Text(
            post.body,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.textSecondary, height: 1.5, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat(Icons.favorite_border_rounded, post.likesCount),
              const SizedBox(width: 16),
              _stat(Icons.chat_bubble_outline_rounded, post.commentsCount),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy_rounded,
                    size: 18, color: AppColors.textMuted),
                tooltip: 'Copy',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: post.body));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Reflection copied'),
                    duration: Duration(seconds: 2),
                  ));
                },
              ),
              if (post.url != null)
                IconButton(
                  icon: const Icon(Icons.open_in_new_rounded,
                      size: 18, color: AppColors.gold),
                  tooltip: 'Open on Quran Reflect',
                  onPressed: () async {
                    final uri = Uri.tryParse(post.url!);
                    if (uri != null) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, int value) => Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text('$value',
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      );
}
