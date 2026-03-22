import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/daily_notification_service.dart';
import '../../../core/services/model_manager.dart';
import '../../../core/services/quran_api_config_service.dart';
import '../../../core/services/quran_user_session_service.dart';
import '../../../core/services/quran_user_sync_service.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/theme/app_theme.dart';

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
  }

  Future<void> _startUserSignIn() async {
    await _userSessionService.startSignIn();
    _handleUserSessionChanged();
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
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 80),
          children: [
            // ── Header ──────────────────────────────────
            Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
            ),
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
                      ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22)
                      : TextButton(
                          onPressed: _downloadModels,
                          child: const Text('Download', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
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
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    if (_isDownloading) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: _downloadProgress.progress,
                          backgroundColor: AppColors.surfaceLight,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(_downloadProgress.progress * 100).round()}% complete',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
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
                style: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.5), fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '﷽',
                style: TextStyle(color: AppColors.gold.withValues(alpha: 0.4), fontSize: 20),
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
              Icon(Icons.notifications_active_rounded, color: AppColors.gold.withValues(alpha: 0.6), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quran Reading Reminder',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _reminderEnabled
                          ? 'Daily reminder at $timeLabel'
                          : 'Get a daily nudge to read Quran',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _reminderEnabled,
                activeColor: AppColors.gold,
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 18, color: AppColors.gold),
                    const SizedBox(width: 10),
                    Text(
                      timeLabel,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text('Change', style: TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w600)),
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
    final environment = _userSessionService.config.environmentLabel;
    final subtitle = isSignedIn
        ? 'Signed in to $environment. Quran Foundation bookmarks, reading progress, and streak sync are enabled.'
        : (_userAuthError?.trim().isNotEmpty == true
            ? _userAuthError!
            : 'Sign in with Quran Foundation OAuth to sync bookmarks, reading progress, and streaks.');

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
                child: Icon(Icons.account_circle_outlined, color: AppColors.gold.withValues(alpha: 0.6), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quran Foundation Account',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
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
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sign In'),
                ),
              if (isSignedIn)
                OutlinedButton(
                  onPressed: isBusy || _isSyncingAccount ? null : _syncAccountNow,
                  child: _isSyncingAccount
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
            child: Icon(icon, color: AppColors.gold.withValues(alpha: 0.6), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          ?trailing,
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
                child: Icon(Icons.volume_up_rounded, color: AppColors.gold.withValues(alpha: 0.6), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Audio Boost',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Boost spoken answers and keep recitation playback at the device speaker volume.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
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
              initialValue: _availableTtsVoices.any(
                (voice) => voice.id == _ttsVoiceId,
              )
                  ? _ttsVoiceId
                  : _availableTtsVoices.first.id,
              dropdownColor: AppColors.surfaceLight,
              decoration: const InputDecoration(
                labelText: 'Voice style',
              ),
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

}