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

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const List<
    ({String label, String subtitle, String prompt, IconData icon})
  >
  _feelingPrompts = [
    (
      label: 'Peaceful',
      subtitle: 'Verses of tranquility',
      prompt: 'I feel at peace and want to reflect',
      icon: Icons.cloud_outlined,
    ),
    (
      label: 'Seeking guidance',
      subtitle: 'Wisdom for difficult choices',
      prompt: 'I need guidance for a difficult decision',
      icon: Icons.psychology_outlined,
    ),
    (
      label: 'Grateful',
      subtitle: 'Reminders of blessings',
      prompt: 'I feel grateful',
      icon: Icons.favorite_outline,
    ),
    (
      label: 'Anxious',
      subtitle: 'Finding inner calm',
      prompt: 'I feel anxious',
      icon: Icons.waves_outlined,
    ),
    (
      label: 'Sad',
      subtitle: 'Comfort in difficult times',
      prompt: 'I feel sad',
      icon: Icons.water_drop_outlined,
    ),
    (
      label: 'Lost',
      subtitle: 'Finding your purpose',
      prompt: 'I feel lost',
      icon: Icons.explore_outlined,
    ),
    (
      label: 'Lonely',
      subtitle: 'You are never alone',
      prompt: 'I feel lonely',
      icon: Icons.person_outline_rounded,
    ),
    (
      label: 'Happy',
      subtitle: 'Celebrate with gratitude',
      prompt: 'I feel happy',
      icon: Icons.wb_sunny_outlined,
    ),
  ];

  static const List<({String label, String prompt})> _suggestedPrompts = [
    (
      label: 'Virtues of Sabr',
      prompt: 'Show me Quran verses about the virtues of patience (Sabr).',
    ),
    (
      label: 'Purpose of life',
      prompt: 'What does the Quran say about the purpose of life?',
    ),
    (
      label: 'Healing verses',
      prompt: 'Show me healing and comforting verses from the Quran.',
    ),
    (
      label: 'Morning focus',
      prompt: 'Give me a Quran reflection for starting the day with focus.',
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
  bool _sourcesExpanded = false;

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

    _homeStateSubscription = ref.listenManual<HomeState>(homeProvider, (
      previous,
      next,
    ) {
      _popupSnapshot = next;
      final responseChanged = previous?.response != next.response;
      final citationsChanged =
          previous?.citations.length != next.citations.length;
      final hadNoResponse = !(previous?.response?.isNotEmpty ?? false);

      if (hadNoResponse && next.voiceState == VoiceState.processing) {
        _popupTraceTag = PerfTrace.nextTag('home.popup');
        _popupCycleSw = PerfTrace.start(_popupTraceTag!, 'ui_cycle');
        _lastPopupLoggedLength = -1;
      }

      if (!(next.response?.isNotEmpty ?? false)) {
        _answerPopupDismissedForCurrentResponse = false;
        if (_sourcesExpanded) {
          setState(() => _sourcesExpanded = false);
        }
        if (_userScrolledUp) setState(() => _userScrolledUp = false);
        return;
      }

      final responseLength = next.response?.length ?? 0;
      if (_popupTraceTag != null && _popupCycleSw != null) {
        if (_lastPopupLoggedLength < 0) {
          PerfTrace.mark(
            _popupTraceTag!,
            'first_response_visible',
            _popupCycleSw!,
          );
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
        if (_sourcesExpanded) {
          setState(() => _sourcesExpanded = false);
        }
        _scheduleAutoScroll(isStreaming: next.isStreaming);
        if (!_isAnswerPopupVisible &&
            !_answerPopupDismissedForCurrentResponse) {
          _showAnswerPopup();
        }
      }
    });
  }

  ScrollController get _activeScrollController => _isAnswerPopupVisible
      ? _popupScrollController
      : _responseScrollController;

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
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceLight,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Noor AI',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          fontSize: 22,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => context.go('/settings'),
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: AppColors.gold,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(child: _buildResponseArea(state)),

                if (!keyboardOpen &&
                    state.transcription != null &&
                    state.transcription!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
                    child: Column(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(
                            _statusText(state.voiceState),
                            key: ValueKey(state.voiceState),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: state.voiceState == VoiceState.idle
                                      ? AppColors.textMuted
                                      : AppColors.gold85,
                                  fontWeight:
                                      state.voiceState == VoiceState.idle
                                      ? FontWeight.w500
                                      : FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight.withValues(
                              alpha: 0.6,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '"${state.transcription}"',
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.textSecondary.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (!keyboardOpen && state.voiceState != VoiceState.idle)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _statusText(state.voiceState),
                        key: ValueKey(state.voiceState),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gold85,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                // ── Text input ────────────────────────────
                Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    keyboardOpen ? 12 : 12 + bottomPadding,
                  ),
                  decoration: const BoxDecoration(
                    gradient: AppColors.footerFadeGradient,
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
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Ask about the Quran...',
                              hintStyle: TextStyle(
                                color: AppColors.textMuted.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              suffixIcon: _hasInputText
                                  ? IconButton(
                                      onPressed: () => _textController.clear(),
                                      icon: Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: AppColors.textMuted,
                                      ),
                                      tooltip: 'Clear',
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
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
                              : () => ref
                                    .read(homeProvider.notifier)
                                    .toggleVoice(),
                          icon: Icon(
                            isStopActionVisible
                                ? Icons.stop_rounded
                                : _hasInputText
                                ? Icons.arrow_upward_rounded
                                : Icons.mic_rounded,
                            size: 20,
                            color: isStopActionVisible
                                ? Colors.white
                                : _hasInputText
                                ? AppColors.background
                                : AppColors.textMuted,
                          ),
                          tooltip: isStopActionVisible
                              ? 'Stop'
                              : _hasInputText
                              ? 'Send'
                              : 'Speak',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isAnswerPopupVisible) _buildAnswerPopupOverlay(),
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
                  color: AppColors.errorAlpha10,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.error,
                  size: 28,
                ),
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
                        color: AppColors.gold60,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Thinking...',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
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

    // Empty state
    return _buildFeelingChooser();
  }

  Widget _buildFeelingChooser() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero branding
          _buildHeroBranding(),
          const SizedBox(height: 28),

          // Quick suggestions
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              'TRY ASKING',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textMuted,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _suggestedPrompts
                .map(
                  (item) => _quickPromptChip(
                    item.label,
                    Icons.auto_awesome_rounded,
                    prompt: item.prompt,
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 28),

          // Action grid
          _buildActionGrid(),
          const SizedBox(height: 28),

          // Feelings section
          _buildFeelingsSection(),
        ],
      ),
    );
  }

  Widget _buildHeroBranding() {
    return Center(
      child: Column(
        children: [
          Text(
            'Divine guidance for your heart',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Illuminate your path.',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              fontSize: 34,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    return Row(
      children: [
        Expanded(
          child: _actionCard(
            icon: Icons.auto_stories_rounded,
            bgIcon: Icons.today_rounded,
            title: 'Daily Ayah',
            subtitle: 'Verse of the day reflection',
            route: '/daily-ayah',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionCard(
            icon: Icons.explore_rounded,
            bgIcon: Icons.menu_book_rounded,
            title: 'Browse Quran',
            subtitle: 'Explore by Surah & Juz',
            route: '/quran',
          ),
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required IconData bgIcon,
    required String title,
    required String subtitle,
    required String route,
  }) {
    return GestureDetector(
      onTap: () => context.go(route),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -8,
              right: -8,
              child: Icon(bgIcon, size: 56, color: AppColors.textMuted08),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 28, color: AppColors.gold),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeelingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start with a feeling',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Guided wisdom for your emotional state',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._feelingPrompts.map((item) => _buildFeelingRow(item)),
      ],
    );
  }

  Widget _buildFeelingRow(
    ({String label, String subtitle, String prompt, IconData icon}) item,
  ) {
    return GestureDetector(
      onTap: () {
        _textController.text = item.prompt;
        _sendText(item.prompt);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.icon, size: 22, color: AppColors.gold),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  // _quickActionChip & _greeting removed — replaced by new design

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
        color: AppColors.black32,
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
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      border: Border.all(color: AppColors.gold12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.black28,
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
                            color: AppColors.textMuted40,
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
                                  color: AppColors.gold10,
                                ),
                                child: const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 16,
                                  color: AppColors.gold,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Answer',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed:
                                    state.response == null ||
                                        state.response!.trim().isEmpty
                                    ? null
                                    : () => _copyAnswer(state.response!),
                                icon: Icon(
                                  Icons.copy_rounded,
                                  size: 20,
                                  color: AppColors.textSecondary,
                                ),
                                tooltip: 'Copy answer',
                              ),
                              IconButton(
                                onPressed:
                                    state.response == null ||
                                        state.response!.trim().isEmpty
                                    ? null
                                    : () => _shareAsPost(state),
                                icon: Icon(
                                  Icons.share_rounded,
                                  size: 20,
                                  color: AppColors.textSecondary,
                                ),
                                tooltip: 'Share as reflection',
                              ),
                              IconButton(
                                onPressed: _hideAnswerPopup,
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 20,
                                  color: AppColors.textSecondary,
                                ),
                                tooltip: 'Close',
                              ),
                            ],
                          ),
                        ),
                        Container(height: 0.5, color: AppColors.divider),
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
                                    color: AppColors.black18,
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

  void _shareAsPost(HomeState state) {
    final body = state.response?.trim() ?? '';
    if (body.isEmpty) return;

    final verse = state.currentVerse;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SharePostSheet(
        body: body,
        verse: verse,
      ),
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
                  color: AppColors.gold60,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Preparing your answer...',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
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
                colors: [AppColors.card, AppColors.gold04],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold15),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold10,
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
            styleSheet: AppTheme.markdownStyle,
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
                    color: AppColors.gold40,
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
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _sourcesExpanded = !_sourcesExpanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_outlined, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sources (${state.citations.length})',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  _sourcesExpanded ? 'Hide' : 'Show',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _sourcesExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (_sourcesExpanded) ...[
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
                    if (citation.excerpt != null &&
                        citation.excerpt!.isNotEmpty) ...[
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
                isBookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_outline_rounded,
                size: 16,
                color: AppColors.gold,
              ),
              label: Text(
                isBookmarked ? 'Saved' : 'Save',
                style: const TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(color: AppColors.gold25),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          '"$text"',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
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

class _SharePostSheet extends StatefulWidget {
  const _SharePostSheet({required this.body, this.verse});

  final String body;
  final Verse? verse;

  @override
  State<_SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<_SharePostSheet> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.body);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (!QuranUserSessionService.instance.isSignedIn) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Sign in first to share reflections.')),
        );
      return;
    }

    setState(() => _saving = true);

    final sync = QuranUserSyncService.instance;
    final result = await sync.createPost(
      body: text,
      verseKeys: widget.verse != null
          ? ['${widget.verse!.surahNumber}:${widget.verse!.ayahNumber}']
          : [],
    );

    if (!mounted) return;

    Navigator.of(context).pop();

    String message;
    if (result != null && sync.lastPostError == null) {
      message = 'Reflection saved!';
    } else if (result != null) {
      message = 'Saved as private note (public publishing unavailable).';
    } else {
      message = sync.lastPostError ?? 'Could not save — please try again.';
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Share as Reflection',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                ),
                const Spacer(),
                if (_saving)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton(
                    onPressed: _publish,
                    child: const Text('Publish'),
                  ),
              ],
            ),
            if (widget.verse != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Surah ${widget.verse!.surahNumber}:${widget.verse!.ayahNumber}',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: TextField(
                controller: _controller,
                maxLines: null,
                minLines: 4,
                decoration: InputDecoration(
                  hintText: 'Edit your reflection...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
