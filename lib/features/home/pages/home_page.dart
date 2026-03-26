import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/verse.dart';
import '../../../core/services/quran_user_session_service.dart';
import '../../../core/services/quran_user_sync_service.dart';
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
  static const List<({String label, String prompt, IconData icon})>
      _feelingPrompts = [
    (
      label: 'Anxious',
      prompt: 'I feel anxious',
      icon: Icons.favorite_outline,
    ),
    (
      label: 'Happy',
      prompt: 'I feel happy',
      icon: Icons.wb_sunny_outlined,
    ),
    (
      label: 'Guilty',
      prompt: 'I feel guilty and regretful',
      icon: Icons.hourglass_empty_rounded,
    ),
    (
      label: 'Grateful',
      prompt: 'I feel grateful',
      icon: Icons.volunteer_activism_outlined,
    ),
    (
      label: 'Lonely',
      prompt: 'I feel lonely',
      icon: Icons.person_outline_rounded,
    ),
    (
      label: 'Lost',
      prompt: 'I feel lost',
      icon: Icons.explore_outlined,
    ),
    (
      label: 'Overwhelmed',
      prompt: 'I feel overwhelmed',
      icon: Icons.waves_outlined,
    ),
    (
      label: 'Sad',
      prompt: 'I feel sad',
      icon: Icons.cloud_outlined,
    ),
  ];

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

    // Detect manual upward scroll and pause auto-scroll (both inline and popup controllers)
    _responseScrollController.addListener(_onScrollUpdate);
    _popupScrollController.addListener(_onScrollUpdate);

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
    final isStopActionVisible =
        state.voiceState == VoiceState.processing ||
        state.voiceState == VoiceState.speaking ||
        state.isStreaming;
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
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

                Expanded(
                  child: _buildResponseArea(state),
                ),

                if (!keyboardOpen) ...[
                  AnimatedVoiceButton(
                    state: state.voiceState,
                    onTap: () => ref.read(homeProvider.notifier).toggleVoice(),
                  ),
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
                        onSubmitted: isStopActionVisible ? null : _sendText,
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
                      color: isStopActionVisible
                          ? AppColors.error
                          : _hasInputText
                              ? AppColors.gold
                              : AppColors.surfaceLight,
                      border: isStopActionVisible || _hasInputText
                          ? null
                          : Border.all(color: AppColors.divider),
                    ),
                    child: IconButton(
                      onPressed: isStopActionVisible
                          ? _stopActiveResponse
                          : _hasInputText
                              ? () => _sendText(_textController.text)
                              : null,
                      icon: Icon(
                        isStopActionVisible
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                        size: 20,
                        color: isStopActionVisible
                            ? Colors.white
                            : _hasInputText
                                ? AppColors.background
                                : AppColors.textMuted,
                      ),
                      tooltip: isStopActionVisible ? 'Stop' : 'Send',
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

    // Keep the home body clean. Answers are shown in the popup only.
    if (state.response != null && state.response!.isNotEmpty) {
      return _buildFeelingChooser();
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
    return _buildFeelingChooser();
  }

  Widget _buildFeelingChooser() {
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
                    'How are you feeling today?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose a feeling and Noor will bring Quran-based comfort, perspective, or gratitude reminders.',
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
                    spacing: 10,
                    runSpacing: 12,
                    children: _feelingPrompts
                        .map(
                          (item) => _quickPromptChip(
                            item.label,
                            item.icon,
                            prompt: item.prompt,
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'You can still type your own question below.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted.withValues(alpha: 0.82),
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
                                onPressed: state.response == null || state.response!.trim().isEmpty || state.isStreaming
                                    ? null
                                    : () => _shareAsPost(state),
                                icon: Icon(Icons.share_rounded, size: 20, color: AppColors.textSecondary),
                                tooltip: 'Share as post',
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
                                child: _buildAnswerContent(state),
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

  Future<void> _shareAsPost(HomeState state) async {
    final response = state.response!.trim();
    // Verse keys from citations
    final verseKeys = state.citations.map((c) => c.verseKey).toList(growable: false);

    // Check sign-in state before opening the sheet
    final isSignedIn = QuranUserSessionService.instance.isSignedIn;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SharePostSheet(
        responseText: response,
        verseKeys: verseKeys,
        isSignedIn: isSignedIn,
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
          Container(
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
          MarkdownBody(
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              citation.quranSourceLabel,
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tafsir: ${citation.tafsirSourceLabel}',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
                  const SizedBox(height: 8),
                  Text(
                    'Tap to open full Quran verse and tafsir',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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

  void _stopActiveResponse() {
    ref.read(homeProvider.notifier).stop();
  }

  Widget _quickPromptChip(String text, IconData icon, {String? prompt}) {
    return GestureDetector(
      onTap: () {
        final resolvedPrompt = prompt ?? text;
        _textController.text = resolvedPrompt;
        _sendText(resolvedPrompt);
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

  void _onScrollUpdate() {
    final sc = _activeScrollController;
    if (!sc.hasClients) return;
    final pos = sc.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 8.0;
    if (!atBottom && pos.userScrollDirection == ScrollDirection.forward) {
      if (!_userScrolledUp) setState(() => _userScrolledUp = true);
    } else if (atBottom) {
      if (_userScrolledUp) setState(() => _userScrolledUp = false);
    }
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
// ── Share-as-Post bottom sheet ────────────────────────────────────────────────

class _SharePostSheet extends StatefulWidget {
  const _SharePostSheet({
    required this.responseText,
    required this.verseKeys,
    required this.isSignedIn,
  });

  final String responseText;
  final List<String> verseKeys;
  final bool isSignedIn;

  @override
  State<_SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<_SharePostSheet> {
  late final TextEditingController _bodyController;
  bool _isPosting = false;
  String? _error;

  static const int _maxChars = 10000;
  static const int _minChars = 6;

  @override
  void initState() {
    super.initState();
    // Pre-fill with a trimmed version of the LLM response, capped at 10 000 chars.
    final trimmed = widget.responseText.trim();
    _bodyController = TextEditingController(
      text: trimmed.length > _maxChars ? trimmed.substring(0, _maxChars) : trimmed,
    );
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _bodyController.text.trim();
    if (body.length < _minChars) {
      setState(() => _error = 'Post must be at least $_minChars characters.');
      return;
    }

    setState(() {
      _isPosting = true;
      _error = null;
    });

    final post = await QuranUserSyncService.instance.createPost(
      body: body,
      verseKeys: widget.verseKeys,
    );

    if (!mounted) return;

    if (post != null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Shared to QuranReflect ✓')),
        );
    } else {
      setState(() {
        _isPosting = false;
        _error = 'Could not post. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final charCount = _bodyController.text.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold.withValues(alpha: 0.1),
                  ),
                  child: const Icon(Icons.share_rounded, size: 16, color: AppColors.gold),
                ),
                const SizedBox(width: 10),
                Text(
                  'Share to QuranReflect',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: AppColors.divider),
          // Body
          if (!widget.isSignedIn)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 40, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'Sign in required',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Go to Settings → Account to sign in with your Quran Foundation account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Verse tags
                  if (widget.verseKeys.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.verseKeys.map((k) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          k,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.gold,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 14),
                  ],
                  // Editable body
                  AnimatedBuilder(
                    animation: _bodyController,
                    builder: (_, __) {
                      return TextField(
                        controller: _bodyController,
                        maxLines: 8,
                        maxLength: _maxChars,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.55),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.divider),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.divider),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.gold.withValues(alpha: 0.4)),
                          ),
                          counterStyle: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                        onChanged: (_) => setState(() => _error = null),
                      );
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_isPosting || charCount < _minChars) ? null : _submit,
                      icon: _isPosting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(_isPosting ? 'Posting...' : 'Post to QuranReflect'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
        ],
      ),
    );
  }
}