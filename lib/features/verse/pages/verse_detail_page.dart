import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/verse.dart';
import '../../../core/services/llm_service.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/services/quran_user_session_service.dart';
import '../../../core/services/quran_user_sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/prompt_templates.dart';
import '../../bookmarks/providers/bookmarks_provider.dart';

class VerseDetailPage extends ConsumerStatefulWidget {
  const VerseDetailPage({
    super.key,
    required this.surahNumber,
    required this.ayahNumber,
  });

  final int surahNumber;
  final int ayahNumber;

  @override
  ConsumerState<VerseDetailPage> createState() => _VerseDetailPageState();
}

class _VerseDetailPageState extends ConsumerState<VerseDetailPage> {
  late final Future<_VerseDetailData> _detailFuture;


  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  @override
  Widget build(BuildContext context) {
    final verseKey = '${widget.surahNumber}:${widget.ayahNumber}';
    final bookmarks = ref.watch(bookmarksProvider);
    final isBookmarked = bookmarks.bookmarks.any((b) => b.verseKey == verseKey);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Verse $verseKey',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: AppColors.textSecondary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          FutureBuilder<_VerseDetailData>(
            future: _detailFuture,
            builder: (context, snapshot) {
              final verse = snapshot.data?.verse;
              if (verse == null) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      color: isBookmarked ? AppColors.gold : AppColors.textSecondary,
                      size: 22,
                    ),
                    tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark',
                    onPressed: () => _toggleBookmark(verse, isBookmarked),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.edit_note_rounded,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                    tooltip: 'Write reflection',
                    onPressed: () => _showReflectSheet(verse),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.copy_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    tooltip: 'Copy verse',
                    onPressed: () => _copyVerse(verse),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<_VerseDetailData>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            );
          }

          final detail = snapshot.data;
          if (detail == null || detail.verse == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.textMuted,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Could not load verse $verseKey.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(context).padding.bottom + 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Verse card ─────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.cardHighlight,
                        AppColors.card,
                        AppColors.gold04,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.gold20, width: 0.8),
                  ),
                  child: Column(
                    children: [
                      // Verse key badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gold12,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.gold20),
                        ),
                        child: Text(
                          detail.verse!.verseKey,
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Arabic text
                      Text(
                        detail.verse!.arabicText ?? '',
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 28,
                          height: 2.1,
                        ),
                      ),

                      if ((detail.verse!.translationText ?? '').isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Container(height: 0.5, color: AppColors.gold20),
                        const SizedBox(height: 18),
                        Text(
                          detail.verse!.translationText!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                            height: 1.65,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Tafsir ──────────────────────────────
                _SectionLabel(label: 'Tafsir'),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.divider, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((detail.tafsirSource ?? '').isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold08,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            detail.tafsirSource!,
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        (detail.tafsirText ?? '').isNotEmpty
                            ? detail.tafsirText!
                            : 'No tafsir is available for this verse right now.',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.65,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _toggleBookmark(Verse verse, bool isCurrentlyBookmarked) {
    if (isCurrentlyBookmarked) {
      ref.read(bookmarksProvider.notifier).remove(verse.verseKey);
    } else {
      ref.read(bookmarksProvider.notifier).toggleVerse(
        verse,
        surahName: 'Surah ${verse.surahNumber}',
      );
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _showReflectSheet(Verse verse) async {
    final isSignedIn = QuranUserSessionService.instance.isSignedIn;
    if (!isSignedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Sign in to publish reflections to QuranReflect.'),
          ),
        );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReflectSheet(verse: verse),
    );
  }

  Future<void> _copyVerse(Verse verse) async {
    final parts = [
      if ((verse.arabicText ?? '').isNotEmpty) verse.arabicText!,
      if ((verse.translationText ?? '').isNotEmpty) verse.translationText!,
      '— ${verse.verseKey}',
    ];
    await Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Verse copied to clipboard.')),
      );
  }

  Future<_VerseDetailData> _loadDetail() async {
    final results = await Future.wait<dynamic>([
      QuranApiService.instance.getVerse(
        widget.surahNumber,
        widget.ayahNumber,
      ),
      QuranApiService.instance.getVerseTafsir(
        widget.surahNumber,
        widget.ayahNumber,
      ),
      QuranApiService.instance.getVerseTafsirSource(
        widget.surahNumber,
        widget.ayahNumber,
      ),
    ]);

    return _VerseDetailData(
      verse: results[0] as Verse?,
      tafsirText: results[1] as String?,
      tafsirSource: results[2] as String?,
    );
  }

}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.gold,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ── Reflect Sheet ─────────────────────────────────────────────────────────────

class _ReflectSheet extends StatefulWidget {
  final Verse verse;
  const _ReflectSheet({required this.verse});

  @override
  State<_ReflectSheet> createState() => _ReflectSheetState();
}

class _ReflectSheetState extends State<_ReflectSheet> {
  final _controller = TextEditingController();
  bool _isPosting = false;
  String? _error;
  bool _posted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.length < 6) {
      setState(() => _error = 'Please write at least 6 characters.');
      return;
    }
    setState(() {
      _isPosting = true;
      _error = null;
    });

    final post = await QuranUserSyncService.instance.createPost(
      body: text,
      verseKeys: [widget.verse.verseKey],
    );

    if (!mounted) return;

    if (post != null) {
      setState(() {
        _isPosting = false;
        _posted = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.of(context).pop();
    } else {
      setState(() {
        _isPosting = false;
        _error = QuranUserSyncService.instance.lastPostError ??
            'Could not publish. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final verse = widget.verse;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: AppColors.gold12,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit_note_rounded,
                      size: 17,
                      color: AppColors.gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Write a Reflection',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Verse reference chip
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
                  verse.verseKey,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Text field
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider, width: 0.5),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: 5,
                  minLines: 3,
                  autofocus: true,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                  decoration: const InputDecoration(
                    hintText:
                        'Share your reflection on this verse with the community…',
                    hintStyle: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Publish button
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _isPosting || _posted ? null : _post,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: _posted || _isPosting
                          ? null
                          : AppColors.goldGradient,
                      color: _posted
                          ? AppColors.success
                          : _isPosting
                          ? AppColors.surfaceLight
                          : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isPosting)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.gold,
                            ),
                          )
                        else if (_posted)
                          const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          )
                        else
                          const Icon(
                            Icons.send_rounded,
                            color: Colors.black,
                            size: 16,
                          ),
                        const SizedBox(width: 8),
                        Text(
                          _posted
                              ? 'Published!'
                              : _isPosting
                              ? 'Publishing…'
                              : 'Publish to QuranReflect',
                          style: TextStyle(
                            color: _posted
                                ? Colors.white
                                : _isPosting
                                ? AppColors.textMuted
                                : Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Your reflection will be shared on QuranReflect',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerseDetailData {
  const _VerseDetailData({
    required this.verse,
    required this.tafsirText,
    required this.tafsirSource,
  });

  final Verse? verse;
  final String? tafsirText;
  final String? tafsirSource;
}
