import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:animate_do/animate_do.dart';

import '../../../core/models/verse.dart';
import '../../../core/theme/app_theme.dart';
import '../../bookmarks/providers/bookmarks_provider.dart';
import '../providers/home_provider.dart';
import '../widgets/animated_voice_button.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _textController = TextEditingController();
  final _responseScrollController = ScrollController();
  ProviderSubscription<HomeState>? _homeStateSubscription;
  bool _isAnswerPopupVisible = false;
  bool _answerPopupDismissedForCurrentResponse = false;

  @override
  void initState() {
    super.initState();
    _homeStateSubscription = ref.listenManual<HomeState>(
      homeProvider,
      (previous, next) {
        final responseChanged = previous?.response != next.response;
        final citationsChanged = previous?.citations.length != next.citations.length;

        if (!(next.response?.isNotEmpty ?? false)) {
          _answerPopupDismissedForCurrentResponse = false;
          return;
        }

        if ((responseChanged || citationsChanged) &&
            (next.response?.isNotEmpty ?? false)) {
          _scheduleAutoScroll();
          if (!_isAnswerPopupVisible && !_answerPopupDismissedForCurrentResponse) {
            _showAnswerPopup();
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _homeStateSubscription?.close();
    _responseScrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: FadeInDown(
                duration: const Duration(milliseconds: 600),
                child: Column(
                  children: [
                    Text(
                      'Noor AI',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: AppColors.gold,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your Quran Companion',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            // Response area
            Expanded(
              child: _buildResponseArea(state),
            ),

            // Voice button
            FadeInUp(
              duration: const Duration(milliseconds: 500),
              child: AnimatedVoiceButton(
                state: state.voiceState,
                onTap: () => ref.read(homeProvider.notifier).toggleVoice(),
              ),
            ),

            // Status text
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _statusText(state.voiceState),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),

            // Text input fallback
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Ask about the Quran...',
                        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onSubmitted: _sendText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _sendText(_textController.text),
                    icon: const Icon(Icons.send_rounded, color: AppColors.gold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponseArea(HomeState state) {
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            state.error!,
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Empty state
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_stories_rounded,
                    size: 48,
                    color: AppColors.gold.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tap the mic or type to ask\nabout the Quran',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.6),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAnswerPopup() async {
    if (!mounted || _isAnswerPopupVisible) {
      return;
    }

    _isAnswerPopupVisible = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, child) {
            final state = ref.watch(homeProvider);

            return FractionallySizedBox(
              heightFactor: 0.9,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.16),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
                      child: Row(
                        children: [
                          Text(
                            'Answer',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: state.response == null || state.response!.trim().isEmpty
                                ? null
                                : () => _copyAnswer(state.response!),
                            icon: const Icon(
                              Icons.copy_rounded,
                              color: AppColors.textPrimary,
                            ),
                            tooltip: 'Copy answer',
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppColors.textPrimary,
                            ),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: AppColors.gold.withValues(alpha: 0.12),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _responseScrollController,
                        padding: EdgeInsets.fromLTRB(
                          20,
                          20,
                          20,
                          20 + MediaQuery.of(context).viewInsets.bottom,
                        ),
                        child: _buildAnswerContent(state),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    _isAnswerPopupVisible = false;
    _answerPopupDismissedForCurrentResponse =
        ref.read(homeProvider).response?.isNotEmpty ?? false;
  }

  Future<void> _copyAnswer(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: trimmed));
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Answer copied to clipboard.')),
      );
  }

  Widget _buildAnswerContent(HomeState state) {
    if (state.response == null || state.response!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.gold.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Preparing your answer...',
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.88),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.currentVerse != null)
          FadeIn(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    state.currentVerse!.arabicText ?? '',
                    style: const TextStyle(
                      fontSize: 24,
                      color: AppColors.gold,
                      height: 2,
                    ),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.currentVerse!.translationText ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.currentVerse!.verseKey,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.gold.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildVerseActions(state.currentVerse!),
                ],
              ),
            ),
          ),
        FadeIn(
          child: MarkdownBody(
            data: state.response!,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.6),
              strong: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
              h1: const TextStyle(color: AppColors.gold, fontSize: 22),
              h2: const TextStyle(color: AppColors.gold, fontSize: 18),
              blockquoteDecoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: AppColors.gold, width: 3)),
              ),
            ),
          ),
        ),
        if (state.citations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _buildCitations(state),
          ),
        if (state.isStreaming)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.gold.withValues(alpha: 0.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCitations(HomeState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sources',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.gold,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        ...state.citations.map((citation) {
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openVerseDetail(citation.verseKey),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        citation.verseKey,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: AppColors.gold.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    citation.sourceLabel,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (citation.excerpt != null && citation.excerpt!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      citation.excerpt!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.9),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _statusText(VoiceState voiceState) {
    switch (voiceState) {
      case VoiceState.idle:
        return 'Tap to speak';
      case VoiceState.listening:
        return 'Listening...';
      case VoiceState.processing:
        return 'Thinking...';
      case VoiceState.speaking:
        return 'Speaking...';
    }
  }

  Widget _buildVerseActions(Verse verse) {
    return FutureBuilder<bool>(
      key: ValueKey('bookmark_${verse.verseKey}'),
      future: ref.read(bookmarksProvider.notifier).isBookmarked(verse.verseKey),
      builder: (context, snapshot) {
        final isBookmarked = snapshot.data ?? false;

        return Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _toggleBookmark(verse),
              icon: Icon(
                isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                size: 18,
                color: AppColors.gold,
              ),
              label: Text(isBookmarked ? 'Saved' : 'Save'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleBookmark(Verse verse) async {
    final added = await ref.read(bookmarksProvider.notifier).toggleVerse(verse);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? 'Saved verse ${verse.verseKey} to bookmarks.'
              : 'Removed verse ${verse.verseKey} from bookmarks.',
        ),
      ),
    );

    setState(() {});
  }

  void _sendText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.clear();
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

  void _scheduleAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_responseScrollController.hasClients) {
        return;
      }

      final target = _responseScrollController.position.maxScrollExtent;
      _responseScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
}
