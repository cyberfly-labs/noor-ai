import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/reading_goal.dart';
import '../../../core/services/daily_notification_service.dart';
import '../../../core/services/llm_service.dart';
import '../../../core/services/model_manager.dart';
import '../../../core/services/quran_api_config_service.dart';
import '../../../core/services/quran_user_session_service.dart';
import '../../../core/services/quran_user_sync_service.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../reading_goals/providers/reading_goals_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _modelsDownloaded = false;
  bool _isDownloading = false;
  DownloadProgress _downloadProgress = DownloadProgress.zero();
  StreamSubscription<DownloadProgress>? _progressSubscription;
  String _downloadStatus = '';
  QuranApiConfig? _quranApiConfig;
  final QuranUserSessionService _userSessionService =
      QuranUserSessionService.instance;
  QuranUserSession? _userSession;
  String? _userAuthError;
  bool _isSyncingAccount = false;
  double _ttsGain = 1.8;
  double _playbackVolume = 1.0;
  String _ttsVoiceId = 'F1';
  List<TtsVoiceOption> _availableTtsVoices = const <TtsVoiceOption>[];
  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 6, minute: 0);

  @override
  void initState() {
    super.initState();
    _checkModels();
    _loadQuranApiConfig();
    _loadUserAuthState();
    _loadAudioSettings();
    _loadReminderSettings();
    Future.microtask(() => ref.read(readingGoalsProvider.notifier).load());
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _userSessionService.removeListener(_handleUserSessionChanged);
    super.dispose();
  }

  Future<void> _checkModels() async {
    final mm = ModelManager.instance;
    await mm.initialize();
    final downloaded = await mm.areAllModelsDownloaded();
    if (mounted) {
      setState(() => _modelsDownloaded = downloaded);
    }
  }

  Future<void> _loadQuranApiConfig() async {
    final service = QuranApiConfigService.instance;
    await service.initialize();
    if (mounted) {
      setState(() {
        _quranApiConfig = service.config;
      });
    }
  }

  Future<void> _loadUserAuthState() async {
    await _userSessionService.initialize();
    _userSessionService.removeListener(_handleUserSessionChanged);
    _userSessionService.addListener(_handleUserSessionChanged);
    _handleUserSessionChanged();
  }

  void _handleUserSessionChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      _userSession = _userSessionService.session;
      _userAuthError = _userSessionService.lastAuthError;
    });

    unawaited(ref.read(readingGoalsProvider.notifier).load(silent: true));
  }

  Future<void> _startUserSignIn() async {
    final launched = await _userSessionService.startSignIn();
    _handleUserSessionChanged();

    if (!mounted || launched) {
      return;
    }

    final message = _userSessionService.lastAuthError?.trim();
    if (message == null || message.isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signOutUser() async {
    await _userSessionService.signOut();
    _handleUserSessionChanged();
  }

  Future<void> _syncAccountNow() async {
    if (_isSyncingAccount) {
      return;
    }

    setState(() {
      _isSyncingAccount = true;
    });

    try {
      await QuranUserSyncService.instance.syncNow();
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingAccount = false;
        });
      }
    }
  }

  void _loadReminderSettings() {
    final svc = DailyNotificationService.instance;
    _reminderEnabled = svc.enabled;
    _reminderTime = TimeOfDay(hour: svc.hour, minute: svc.minute);
  }

  Future<void> _toggleReminder(bool value) async {
    final svc = DailyNotificationService.instance;
    if (value) {
      final granted = await svc.requestPermission();
      if (!granted) return;
      await svc.enable(hour: _reminderTime.hour, minute: _reminderTime.minute);
    } else {
      await svc.disable();
    }
    if (mounted) setState(() => _reminderEnabled = svc.enabled);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              surface: AppColors.surfaceLight,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() => _reminderTime = picked);
    final svc = DailyNotificationService.instance;
    await svc.setTime(hour: picked.hour, minute: picked.minute);
  }

  Future<void> _loadAudioSettings() async {
    await VoiceService.instance.initializeAudioSettings();
    final voices = await VoiceService.instance.listAvailableTtsVoices();
    if (!mounted) {
      return;
    }

    setState(() {
      _ttsGain = VoiceService.instance.ttsGain;
      _playbackVolume = VoiceService.instance.playbackVolume;
      _ttsVoiceId = VoiceService.instance.ttsVoiceId;
      _availableTtsVoices = voices;
    });
  }

  Future<void> _downloadModels() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = DownloadProgress.zero();
      _downloadStatus = 'Starting downloads...';
    });

    final mm = ModelManager.instance;
    await mm.initialize();

    await _progressSubscription?.cancel();
    _progressSubscription = mm.downloadProgress.listen((progress) {
      if (mounted) {
        setState(() {
          _downloadProgress = progress;
          _downloadStatus = _formatDownloadStatus(progress);
        });
      }
    });

    try {
      await mm.downloadAllModels();
      await mm.completeOnboarding();
      await _progressSubscription?.cancel();
      await _loadAudioSettings();
      unawaited(LlmService.instance.initialize());

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _modelsDownloaded = true;
          _downloadProgress = const DownloadProgress(
            bytesReceived: 0,
            totalBytes: 0,
            progress: 1,
            currentFileProgress: 1,
          );
          _downloadStatus = 'All models downloaded!';
        });
      }
    } catch (_) {
      await _progressSubscription?.cancel();
      rethrow;
    }
  }

  String _formatDownloadStatus(DownloadProgress progress) {
    final percent = (progress.progress * 100).round();
    final model = progress.modelName;
    final file = progress.currentFile;

    if (model == null || file == null) {
      return 'Downloading models... $percent%';
    }

    return '$model • $file • $percent%';
  }

  @override
  Widget build(BuildContext context) {
    final goalsState = ref.watch(readingGoalsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).padding.bottom + 80,
          ),
          children: [
            _buildOverviewCard(),
            const SizedBox(height: 24),

            _sectionHeader('AI Models'),
            _settingCard(
              icon: Icons.download_rounded,
              title: 'On-Device Models',
              subtitle: _modelsDownloaded
                  ? 'All models downloaded'
                  : 'Download models for offline use',
              trailing: _isDownloading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _downloadProgress.progress > 0
                            ? _downloadProgress.progress
                            : null,
                        color: AppColors.gold,
                      ),
                    )
                  : _modelsDownloaded
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green,
                      size: 22,
                    )
                  : TextButton(
                      onPressed: _downloadModels,
                      child: const Text(
                        'Download',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
            if (_downloadStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _downloadStatus,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (_isDownloading) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: _downloadProgress.progress,
                          backgroundColor: AppColors.surfaceLight,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.gold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(_downloadProgress.progress * 100).round()}% complete',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 20),
            _sectionHeader('Audio'),
            _audioBoostCard(),
            const SizedBox(height: 20),
            _sectionHeader('Daily Reminder'),
            _dailyReminderCard(),
            const SizedBox(height: 20),
            _sectionHeader('Reading Goals'),
            _readingGoalsCard(goalsState),
            const SizedBox(height: 20),
            _sectionHeader('Quran Account'),
            _quranAccountCard(),
            const SizedBox(height: 20),
            _sectionHeader('About'),
            _settingCard(
              icon: Icons.info_outline_rounded,
              title: 'Noor AI',
              subtitle: 'Version 1.0.0',
            ),
            _settingCard(
              icon: Icons.menu_book_rounded,
              title: 'Quran Data',
              subtitle: _quranApiConfig?.providerLabel ?? 'Loading provider...',
            ),
            _settingCard(
              icon: Icons.psychology_outlined,
              title: 'AI Engine',
              subtitle: 'MNN + Qwen3.5 + Whisper on-device',
            ),
            const SizedBox(height: 20),
            _sectionHeader('Acknowledgements'),
            _settingCard(
              icon: Icons.favorite_outline_rounded,
              title: 'Open Source',
              subtitle: 'Built with Flutter, MNN, Edgemind Core',
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                'Made with devotion',
                style: TextStyle(color: AppColors.textMuted50, fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '﷽',
                style: TextStyle(color: AppColors.gold40, fontSize: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyReminderCard() {
    final timeLabel = _reminderTime.format(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                color: AppColors.gold60,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quran Reading Reminder',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _reminderEnabled
                          ? 'Daily reminder at $timeLabel'
                          : 'Get a daily nudge to read Quran',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _reminderEnabled,
                activeThumbColor: AppColors.gold,
                activeTrackColor: AppColors.gold35,
                onChanged: _toggleReminder,
              ),
            ],
          ),
          if (_reminderEnabled) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickReminderTime,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 18,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      timeLabel,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Change',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quranAccountCard() {
    final session = _userSession;
    final isSignedIn = session?.accessToken.isNotEmpty ?? false;
    final isBusy = _userSessionService.isBusy;
    final subtitle = isSignedIn
        ? 'Signed in with Quran Foundation. Bookmarks, reading goals, reading progress, streak sync, and reflections are enabled.'
        : (_userAuthError?.trim().isNotEmpty == true
              ? _userAuthError!
          : 'Sign in with your Quran Foundation account to sync bookmarks, reading goals, progress, streaks, and share reflections.');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.account_circle_outlined,
                  color: AppColors.gold60,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quran Foundation Account',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isSignedIn)
                FilledButton(
                  onPressed: isBusy ? null : _startUserSignIn,
                  child: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign In'),
                ),
              if (isSignedIn)
                OutlinedButton(
                  onPressed: isBusy || _isSyncingAccount
                      ? null
                      : _syncAccountNow,
                  child: _isSyncingAccount
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sync Now'),
                ),
              if (isSignedIn)
                TextButton(
                  onPressed: isBusy ? null : _signOutUser,
                  child: const Text('Sign Out'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _settingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final trailingWidgets = trailing == null
        ? const <Widget>[]
        : <Widget>[trailing];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: AppColors.gold60, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          ...trailingWidgets,
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    final accountConnected = _userSession?.accessToken.isNotEmpty ?? false;
    final modelsLabel = _modelsDownloaded ? 'Models ready' : 'Models pending';
    final reminderLabel = _reminderEnabled
        ? 'Reminder ${_reminderTime.format(context)}'
        : 'Reminder off';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.cardHighlight,
            AppColors.surfaceLight,
            AppColors.background,
          ],
        ),
        border: Border.all(color: AppColors.gold14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tune downloads, audio, reminders, and your Quran Foundation connection in one place.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _overviewPill(
                icon: _modelsDownloaded
                    ? Icons.cloud_done_rounded
                    : Icons.download_rounded,
                label: modelsLabel,
              ),
              _overviewPill(
                icon: accountConnected
                    ? Icons.verified_user_rounded
                    : Icons.person_outline_rounded,
                label: accountConnected
                    ? 'Account connected'
                    : 'Account not linked',
              ),
              _overviewPill(
                icon: _reminderEnabled
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_rounded,
                label: reminderLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overviewPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.gold08,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.gold12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _audioBoostCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.volume_up_rounded,
                  color: AppColors.gold60,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Audio Boost',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Boost spoken answers and keep recitation playback at the device speaker volume.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_availableTtsVoices.isNotEmpty) ...[
            Text(
              'Spoken answer voice',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue:
                  _availableTtsVoices.any((voice) => voice.id == _ttsVoiceId)
                  ? _ttsVoiceId
                  : _availableTtsVoices.first.id,
              dropdownColor: AppColors.surfaceLight,
              decoration: const InputDecoration(labelText: 'Voice style'),
              items: _availableTtsVoices
                  .map(
                    (voice) => DropdownMenuItem<String>(
                      value: voice.id,
                      child: Text('${voice.label} (${voice.id})'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) async {
                if (value == null) {
                  return;
                }

                setState(() {
                  _ttsVoiceId = value;
                });
                await VoiceService.instance.setTtsVoice(value);
              },
            ),
            const SizedBox(height: 6),
            Text(
              _availableTtsVoices
                      .firstWhere(
                        (voice) => voice.id == _ttsVoiceId,
                        orElse: () => _availableTtsVoices.first,
                      )
                      .subtitle +
                  (_availableTtsVoices.length < 4
                      ? ' Download the latest models to unlock more voices.'
                      : ''),
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Spoken answer boost ${(100 * _ttsGain).round()}%',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Slider(
            value: _ttsGain,
            min: 1.0,
            max: 2.5,
            divisions: 15,
            label: '${(100 * _ttsGain).round()}%',
            activeColor: AppColors.gold,
            onChanged: (value) {
              setState(() {
                _ttsGain = value;
              });
            },
            onChangeEnd: (value) async {
              await VoiceService.instance.setAudioBoost(
                ttsGain: value,
                playbackVolume: _playbackVolume,
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Recitation playback ${(100 * _playbackVolume).round()}%',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Slider(
            value: _playbackVolume,
            min: 0.6,
            max: 1.0,
            divisions: 8,
            label: '${(100 * _playbackVolume).round()}%',
            activeColor: AppColors.gold,
            onChanged: (value) {
              setState(() {
                _playbackVolume = value;
              });
            },
            onChangeEnd: (value) async {
              await VoiceService.instance.setAudioBoost(
                ttsGain: _ttsGain,
                playbackVolume: value,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _readingGoalsCard(ReadingGoalsState goalsState) {
    final isSignedIn = _userSession?.accessToken.isNotEmpty ?? false;
    final activeGoal = goalsState.activeGoal;
    final todayProgress = goalsState.todayProgress;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.flag_outlined,
                  color: AppColors.gold60,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reading Goals',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      !isSignedIn
                          ? 'Sign in to set Quran reading goals and keep progress in sync across devices.'
                          : activeGoal == null
                              ? 'Set a pages, chapters, or juz goal and track it alongside your daily Quran habit.'
                              : _readingGoalSubtitle(activeGoal, todayProgress),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (goalsState.isLoading || goalsState.isSaving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (goalsState.error?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              goalsState.error!,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          if (activeGoal != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${activeGoal.target} ${activeGoal.goalTypeLabel}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (activeGoal.endDate != null)
                        Text(
                          'Due ${DateFormat.yMMMd().format(activeGoal.endDate!.toLocal())}',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  if (todayProgress != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: todayProgress.progress,
                        backgroundColor: AppColors.surfaceLight,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.gold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          todayProgress.summaryLabel,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          todayProgress.onTrack ? 'On track' : 'Keep going',
                          style: TextStyle(
                            color: todayProgress.onTrack
                                ? AppColors.gold
                                : AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isSignedIn)
                FilledButton(
                  onPressed: _userSessionService.isBusy ? null : _startUserSignIn,
                  child: const Text('Sign In'),
                )
              else if (activeGoal == null)
                FilledButton(
                  onPressed: goalsState.isSaving ? null : _createReadingGoal,
                  child: const Text('Create Goal'),
                ),
              if (isSignedIn && activeGoal != null)
                OutlinedButton(
                  onPressed: goalsState.isSaving
                      ? null
                      : () => _editReadingGoal(activeGoal),
                  child: const Text('Edit'),
                ),
              if (isSignedIn && activeGoal != null)
                TextButton(
                  onPressed: goalsState.isSaving
                      ? null
                      : () => _deleteReadingGoal(activeGoal),
                  child: const Text('Delete'),
                ),
              if (isSignedIn)
                TextButton(
                  onPressed: goalsState.isSaving
                      ? null
                      : () => ref.read(readingGoalsProvider.notifier).load(),
                  child: const Text('Refresh'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _readingGoalSubtitle(
    ReadingGoal goal,
    ReadingGoalProgress? progress,
  ) {
    final dueLabel = goal.endDate == null
        ? null
        : DateFormat.yMMMd().format(goal.endDate!.toLocal());
    if (progress != null) {
      final tail = dueLabel == null ? '' : ' • due $dueLabel';
      return '${progress.summaryLabel}$tail';
    }
    if (dueLabel != null) {
      return 'Active goal: ${goal.target} ${goal.goalTypeLabel.toLowerCase()} by $dueLabel.';
    }
    return 'Active goal: ${goal.target} ${goal.goalTypeLabel.toLowerCase()}.';
  }

  Future<void> _createReadingGoal() async {
    final draft = await _openReadingGoalSheet();
    if (draft == null || !mounted) {
      return;
    }

    final success = await ref.read(readingGoalsProvider.notifier).createGoal(
          type: draft.goalType,
          target: draft.target,
          deadline: draft.deadline,
        );
    if (!mounted) {
      return;
    }

    final message = success
        ? 'Reading goal saved.'
        : ref.read(readingGoalsProvider).error ??
            'Could not save reading goal.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editReadingGoal(ReadingGoal goal) async {
    final draft = await _openReadingGoalSheet(initialGoal: goal);
    if (draft == null || !mounted) {
      return;
    }

    final success = await ref.read(readingGoalsProvider.notifier).updateGoal(
          goal: goal,
          type: draft.goalType,
          target: draft.target,
          deadline: draft.deadline,
        );
    if (!mounted) {
      return;
    }

    final message = success
        ? 'Reading goal updated.'
        : ref.read(readingGoalsProvider).error ??
            'Could not update reading goal.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteReadingGoal(ReadingGoal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Delete reading goal?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'This removes your current synced reading goal.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final success = await ref
        .read(readingGoalsProvider.notifier)
        .deleteGoal(goal.id);
    if (!mounted) {
      return;
    }

    final message = success
        ? 'Reading goal deleted.'
        : ref.read(readingGoalsProvider).error ??
            'Could not delete reading goal.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<_ReadingGoalDraft?> _openReadingGoalSheet({
    ReadingGoal? initialGoal,
  }) {
    return showModalBottomSheet<_ReadingGoalDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReadingGoalSheet(initialGoal: initialGoal),
    );
  }
}

class _ReadingGoalDraft {
  const _ReadingGoalDraft({
    required this.goalType,
    required this.target,
    required this.deadline,
  });

  final String goalType;
  final int target;
  final DateTime deadline;
}

class _ReadingGoalSheet extends StatefulWidget {
  const _ReadingGoalSheet({this.initialGoal});

  final ReadingGoal? initialGoal;

  @override
  State<_ReadingGoalSheet> createState() => _ReadingGoalSheetState();
}

class _ReadingGoalSheetState extends State<_ReadingGoalSheet> {
  static const List<String> _goalTypes = <String>['pages', 'chapters', 'juzs'];

  late final TextEditingController _targetController;
  late String _goalType;
  late DateTime _deadline;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _goalType = widget.initialGoal?.goalType ?? 'pages';
    _targetController = TextEditingController(
      text: widget.initialGoal?.target.toString() ?? '5',
    );
    _deadline = widget.initialGoal?.endDate?.toLocal() ??
        DateTime.now().add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              surface: AppColors.surfaceLight,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) {
      return;
    }
    setState(() => _deadline = picked);
  }

  void _submit() {
    final target = int.tryParse(_targetController.text.trim());
    if (target == null || target <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Enter a valid target greater than 0.')),
        );
      return;
    }

    setState(() => _submitting = true);
    Navigator.of(context).pop(
      _ReadingGoalDraft(
        goalType: _goalType,
        target: target,
        deadline: _deadline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
    final isEditing = widget.initialGoal != null;

    return Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isEditing ? 'Edit Goal' : 'Create Goal',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Set a synced Quran reading target for pages, chapters, or juz.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _goalType,
              dropdownColor: AppColors.surfaceLight,
              decoration: const InputDecoration(labelText: 'Goal type'),
              items: _goalTypes
                  .map(
                    (value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value[0].toUpperCase() + value.substring(1),
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _goalType = value);
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _targetController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Target',
                hintText: 'e.g. 5',
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickDeadline,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_rounded,
                      color: AppColors.gold,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Deadline • ${DateFormat.yMMMd().format(_deadline)}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'Change',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(isEditing ? 'Save Goal' : 'Create Goal'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
