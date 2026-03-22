import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:animate_do/animate_do.dart';

import '../../../core/models/verse.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/perf_trace.dart';
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
  final _popupScrollController = ScrollController();
  bool _hasInputText = false;
  DateTime _lastAutoScrollAt = DateTime.fromMillisecondsSinceEpoch(0);
  ProviderSubscription<HomeState>? _homeStateSubscription;
  bool _isAnswerPopupVisible = false;
  bool _answerPopupDismissedForCurrentResponse = false;
  HomeState _popupSnapshot = const HomeState();
  String? _popupTraceTag;
  Stopwatch? _popupCycleSw;
  int _lastPopupLoggedLength = -1;
  /// True while the user has scrolled up during streaming — pauses auto-scroll.
  bool _userScrolledUp = false;

  @override
  void initState() {
    super.initState();

    _textController.addListener(() {
      final hasText = _textController.text.trim().isNotEmpty;
      if (hasText != _hasInputText) {
        setState(() => _hasInputText = hasText);
      }
    });

    // Detect manual upward scroll and pause auto-scroll
    _responseScrollController.addListener(() {
      if (!_responseScrollController.hasClients) return;
      final pos = _responseScrollController.position;
      final atBottom = pos.pixels >= pos.maxScrollExtent - 8.0;
      if (!atBottom && pos.userScrollDirection == ScrollDirection.forward) {
        if (!_userScrolledUp) setState(() => _userScrolledUp = true);
      } else if (atBottom) {
        if (_userScrolledUp) setState(() => _userScrolledUp = false);
      }
    });

    _homeStateSubscription = ref.listenManual<HomeState>(
      homeProvider,
      (previous, next) {
        _popupSnapshot = next;
        final responseChanged = previous?.response != next.response;
        final citationsChanged = previous?.citations.length != next.citations.length;
        final hadNoResponse = !(previous?.response?.isNotEmpty ?? false);

        if (hadNoResponse && next.voiceState == VoiceState.processing) {
          _popupTraceTag = PerfTrace.nextTag('home.popup');
          _popupCycleSw = PerfTrace.start(_popupTraceTag!, 'ui_cycle');
          _lastPopupLoggedLength = -1;
        }

        if (!(next.response?.isNotEmpty ?? false)) {
          _answerPopupDismissedForCurrentResponse = false;
          if (_userScrolledUp) setState(() => _userScrolledUp = false);
          return;
        }

        final responseLength = next.response?.length ?? 0;
        if (_popupTraceTag != null && _popupCycleSw != null) {
          if (_lastPopupLoggedLength < 0) {
            PerfTrace.mark(_popupTraceTag!, 'first_response_visible', _popupCycleSw!);
          }
          if (_isAnswerPopupVisible && responseLength != _lastPopupLoggedLength) {
            PerfTrace.mark(
              _popupTraceTag!,
              'popup_response_len_$responseLength',
              _popupCycleSw!,
            );
          }
        }
        _lastPopupLoggedLength = responseLength;

        if ((responseChanged || citationsChanged) &&
            (next.response?.isNotEmpty ?? false)) {
          _scheduleAutoScroll(isStreaming: next.isStreaming);
          if (!_isAnswerPopupVisible && !_answerPopupDismissedForCurrentResponse) {
            _showAnswerPopup();
          }
        }
      },
    );
  }

  ScrollController get _activeScrollController =>
      _isAnswerPopupVisible ? _popupScrollController : _responseScrollController;

  @override
  void dispose() {
    _homeStateSubscription?.close();
    _popupScrollController.dispose();
    _responseScrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeProvider);
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
            // ── Header ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: FadeInDown(
                duration: const Duration(milliseconds: 500),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.goldGradient,
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, size: 18, color: Color(0xFF060B11)),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Noor AI',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                        ),
                        Text(
                          'Your Quran Companion',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Response area ──────────────────────────
            Expanded(
              child: _buildResponseArea(state),
            ),

            if (!keyboardOpen) ...[
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
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _statusText(state.voiceState),
                    key: ValueKey(state.voiceState),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: state.voiceState == VoiceState.idle
                              ? AppColors.textMuted
                              : AppColors.gold.withValues(alpha: 0.85),
                          fontWeight: state.voiceState == VoiceState.idle
                              ? FontWeight.w500
                              : FontWeight.w600,
                        ),
                  ),
                ),
              ),

              // ASR transcription
              if (state.transcription != null && state.transcription!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '"${state.transcription}"',
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary.withValues(alpha: 0.8),
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                ),
            ],

            // ── Text input ────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(16, 8, 16, keyboardOpen ? 12 : 12 + bottomPadding + 56),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.0),
                    AppColors.background,
                  ],
                  stops: const [0.0, 0.3],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: TextField(
                        controller: _textController,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Ask about the Quran...',
                          hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.8)),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          suffixIcon: _hasInputText
                              ? IconButton(
                                  onPressed: () => _textController.clear(),
                                  icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                                  tooltip: 'Clear',
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onSubmitted: _sendText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hasInputText ? AppColors.gold : AppColors.surfaceLight,
                      border: _hasInputText ? null : Border.all(color: AppColors.divider),
                    ),
                    child: IconButton(
                      onPressed: _hasInputText ? () => _sendText(_textController.text) : null,
                      icon: Icon(
                        Icons.arrow_upward_rounded,
                        size: 20,
                        color: _hasInputText
                            ? AppColors.background
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
          if (_isAnswerPopupVisible)
            _buildAnswerPopupOverlay(),
        ],
      ),
    );
  }

  Widget _buildResponseArea(HomeState state) {
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                state.error!,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Inline response (visible when popup is dismissed or alongside it)
    if (state.response != null && state.response!.isNotEmpty) {
      return GestureDetector(
        onTap: () {
          if (!_isAnswerPopupVisible) _showAnswerPopup();
        },
        child: SingleChildScrollView(
          controller: _isAnswerPopupVisible ? null : _responseScrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: _buildAnswerContent(state),
        ),
      );
    }

    // Processing state — response hasn't arrived yet
    if (state.voiceState == VoiceState.processing) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.gold.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Thinking...',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    // Empty state
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.gold.withValues(alpha: 0.06),
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.12), width: 1.5),
                    ),
                    child: Icon(
                      Icons.mosque_rounded,
                      size: 32,
                      color: AppColors.gold.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Assalamu Alaikum',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap the mic or type to ask\nabout the Quran',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 10,
                    children: [
                      _quickPromptChip('Explain Ayat-ul-Kursi', Icons.menu_book_outlined),
                      _quickPromptChip('Verses for anxiety', Icons.favorite_outline),
                      _quickPromptChip('Meaning of Surah Mulk', Icons.auto_stories_outlined),
                    ],
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
    setState(() {
      _popupSnapshot = ref.read(homeProvider);
      _isAnswerPopupVisible = true;
    });
    if (_popupTraceTag != null && _popupCycleSw != null) {
      PerfTrace.mark(_popupTraceTag!, 'popup_shown', _popupCycleSw!);
    }
  }

  void _hideAnswerPopup() {
    setState(() {
      _isAnswerPopupVisible = false;
      _answerPopupDismissedForCurrentResponse =
          ref.read(homeProvider).response?.isNotEmpty ?? false;
    });
    if (_popupTraceTag != null && _popupCycleSw != null) {
      PerfTrace.end(_popupTraceTag!, 'popup_hidden', _popupCycleSw!);
    }
  }

  Widget _buildAnswerPopupOverlay() {
    final state = _popupSnapshot;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.32),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _hideAnswerPopup,
                child: const SizedBox.expand(),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: FractionallySizedBox(
                  heightFactor: 0.92,
                  widthFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 28,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.textMuted.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.gold.withValues(alpha: 0.1),
                                ),
                                child: const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.gold),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Answer',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: state.response == null || state.response!.trim().isEmpty
                                    ? null
                                    : () => _copyAnswer(state.response!),
                                icon: Icon(Icons.copy_rounded, size: 20, color: AppColors.textSecondary),
                                tooltip: 'Copy answer',
                              ),
                              IconButton(
                                onPressed: _hideAnswerPopup,
                                icon: Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                                tooltip: 'Close',
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 0.5,
                          color: AppColors.divider,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _popupScrollController,
                            padding: EdgeInsets.fromLTRB(
                              20,
                              20,
                              20,
                              20 + MediaQuery.of(context).viewInsets.bottom,
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.divider),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: KeyedSubtree(
                                key: ValueKey(
                                  'popup-${state.response?.length ?? 0}-${state.isStreaming}-${state.citations.length}-${state.currentVerse?.verseKey ?? 'none'}',
                                ),
                                child: _buildAnswerContent(state),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.gold.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Preparing your answer...',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
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
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.card,
                    AppColors.gold.withValues(alpha: 0.04),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.15)),
              ),
              child: Column(
                children: [
                  Text(
                    state.currentVerse!.arabicText ?? '',
                    style: const TextStyle(
                      fontSize: 26,
                      color: AppColors.gold,
                      height: 2.1,
                    ),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    state.currentVerse!.translationText ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      state.currentVerse!.verseKey,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildVerseActions(state.currentVerse!),
                ],
              ),
            ),
          ),
        if (state.isStreaming)
          SelectableText(
            state.response!,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              height: 1.65,
            ),
          )
        else
          FadeIn(
            child: MarkdownBody(
              selectable: true,
              data: state.response!,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.65),
                strong: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700),
                h1: TextStyle(color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.w700),
                h2: TextStyle(color: AppColors.gold, fontSize: 17, fontWeight: FontWeight.w700),
                blockquoteDecoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(left: BorderSide(color: AppColors.gold, width: 3)),
                ),
                blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                codeblockDecoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        if (state.citations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: _buildCitations(state),
          ),
        if (state.isStreaming)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.gold.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Generating...',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCitations(HomeState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.verified_outlined, size: 16, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              'Sources',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...state.citations.map((citation) {
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openVerseDetail(citation.verseKey),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          citation.verseKey,
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          citation.sourceLabel,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                  if (citation.excerpt != null && citation.excerpt!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      citation.excerpt!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
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
                size: 16,
                color: AppColors.gold,
              ),
              label: Text(
                isBookmarked ? 'Saved' : 'Save',
                style: const TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(color: AppColors.gold.withValues(alpha: 0.25)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _quickPromptChip(String text, IconData icon) {
    return GestureDetector(
      onTap: () {
        _textController.text = text;
        _sendText(text);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.gold.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
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

  void _scheduleAutoScroll({required bool isStreaming}) {
    if (_userScrolledUp) return;

    final now = DateTime.now();
    if (now.difference(_lastAutoScrollAt) < const Duration(milliseconds: 140)) {
      return;
    }
    _lastAutoScrollAt = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sc = _activeScrollController;
      if (!mounted || !sc.hasClients || _userScrolledUp) {
        return;
      }

      final target = sc.position.maxScrollExtent;
      if (isStreaming) {
        sc.jumpTo(target);
      } else {
        sc.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
