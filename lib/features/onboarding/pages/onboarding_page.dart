import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/model_manager.dart';
import '../../../core/theme/app_theme.dart';

class StartupGatePage extends StatefulWidget {
  const StartupGatePage({super.key});

  @override
  State<StartupGatePage> createState() => _StartupGatePageState();
}

class _StartupGatePageState extends State<StartupGatePage> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    final modelManager = ModelManager.instance;
    try {
      await modelManager.initialize().timeout(const Duration(seconds: 4));
    } catch (error) {
      debugPrint('StartupGatePage: model manager init timed out: $error');
      _go('/onboarding');
      return;
    }

    if (modelManager.isOnboardingComplete) {
      _go('/home');
      unawaited(_validateModelsInBackground(modelManager));
      return;
    }

    final modelsDownloaded = await _safeModelCheck(modelManager);
    if (!mounted) return;

    if (modelsDownloaded) {
      _go('/home');
      return;
    }

    _go('/onboarding');
  }

  Future<void> _validateModelsInBackground(ModelManager modelManager) async {
    final modelsDownloaded = await _safeModelCheck(
      modelManager,
      forceRefresh: true,
      timeout: const Duration(seconds: 8),
      fallback: true,
    );
    if (!modelsDownloaded) {
      debugPrint('StartupGatePage: background model validation found missing files');
    }
  }

  Future<bool> _safeModelCheck(
    ModelManager modelManager, {
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 3),
    bool fallback = false,
  }) async {
    try {
      return await modelManager
          .areAllModelsDownloaded(forceRefresh: forceRefresh)
          .timeout(timeout);
    } catch (error) {
      debugPrint('StartupGatePage: model status check failed: $error');
      return fallback;
    }
  }

  void _go(String location) {
    if (!mounted || _navigated) {
      return;
    }
    _navigated = true;
    context.go(location);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: AppColors.gold),
            SizedBox(height: 16),
            Text(
              'Starting Noor AI...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final ModelManager _modelManager = ModelManager.instance;

  StreamSubscription<DownloadProgress>? _progressSubscription;
  bool _isChecking = true;
  bool _isDownloading = false;
  bool _modelsDownloaded = false;
  DownloadProgress _downloadProgress = DownloadProgress.zero();
  String _downloadStatus = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkExistingModels();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkExistingModels() async {
    await _modelManager.initialize();
    final downloaded = await _modelManager.areAllModelsDownloaded();

    if (!mounted) return;

    setState(() {
      _isChecking = false;
      _modelsDownloaded = downloaded;
      _downloadStatus = downloaded ? 'Models are ready.' : '';
    });
  }

  Future<void> _downloadModels() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _downloadStatus = 'Downloading models...';
    });

    await _progressSubscription?.cancel();
    _progressSubscription = _modelManager.downloadProgress.listen((progress) {
      if (!mounted) return;
      setState(() {
        _downloadProgress = progress;
        _downloadStatus = _formatDownloadStatus(progress);
      });
    });

    try {
      await _modelManager.downloadAllModels();
      await _modelManager.completeOnboarding();

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _modelsDownloaded = true;
        _downloadProgress = const DownloadProgress(
          bytesReceived: 0,
          totalBytes: 0,
          progress: 1,
          currentFileProgress: 1,
        );
        _downloadStatus = 'Models downloaded successfully.';
      });

      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _continueToApp() async {
    await _modelManager.completeOnboarding();
    if (!mounted) return;
    context.go('/home');
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

  String get _primaryButtonLabel {
    if (_isChecking) {
      return 'Checking device';
    }
    if (_isDownloading) {
      return 'Downloading ${(_downloadProgress.progress * 100).round()}%';
    }
    if (_modelsDownloaded) {
      return 'Enter Noor AI';
    }
    return 'Download Models';
  }

  String get _statusHeadline {
    if (_isChecking) {
      return 'Checking what is already on this device';
    }
    if (_isDownloading) {
      return 'Preparing your offline Quran companion';
    }
    if (_modelsDownloaded) {
      return 'Everything is ready';
    }
    return 'Set up the local models once';
  }

  String get _statusBody {
    if (_isChecking) {
      return 'Noor AI is verifying the voice, retrieval, and response models before opening the app.';
    }
    if (_isDownloading) {
      return 'The first launch downloads the on-device models needed for speech, search, and spoken responses.';
    }
    if (_modelsDownloaded) {
      return 'The required models are present. You can continue straight into the app.';
    }
    return 'After setup, core Quran guidance, semantic search, and speech features stay available without depending on a live network round trip.';
  }

  Color get _statusAccent {
    if (_errorMessage != null) {
      return AppColors.error;
    }
    if (_modelsDownloaded) {
      return AppColors.success;
    }
    return AppColors.gold;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF071019), AppColors.background, Color(0xFF04070B)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wideLayout = constraints.maxWidth >= 760;
              final horizontalPadding = constraints.maxWidth >= 960 ? 48.0 : 24.0;
              final featureWidth = wideLayout
                  ? (constraints.maxWidth - (horizontalPadding * 2) - 14) / 2
                  : constraints.maxWidth - (horizontalPadding * 2);

              return Stack(
                children: [
                  const Positioned(
                    top: -40,
                    right: -32,
                    child: _BackdropOrb(
                      size: 220,
                      color: AppColors.gold,
                      opacity: 0.12,
                    ),
                  ),
                  const Positioned(
                    top: 150,
                    left: -60,
                    child: _BackdropOrb(
                      size: 180,
                      color: AppColors.accent,
                      opacity: 0.08,
                    ),
                  ),
                  SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 28),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppColors.gold.withValues(alpha: 0.18)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  height: 8,
                                  width: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'PRIVATE, ON-DEVICE QURAN COMPANION',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontSize: 11,
                                    letterSpacing: 1.0,
                                    color: AppColors.goldLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF111C28), Color(0xFF09121B)],
                              ),
                              border: Border.all(color: AppColors.gold.withValues(alpha: 0.16)),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.gold.withValues(alpha: 0.06),
                                  blurRadius: 40,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Noor AI',
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    color: AppColors.goldLight,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Built for moments when you want Quran guidance without waiting on the network.',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontSize: wideLayout ? 30 : 26,
                                    height: 1.15,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 620),
                                  child: Text(
                                    'Set up the local voice, search, and response models once. After that, Noor AI can listen, retrieve relevant ayat, and answer with far less dependence on cloud round trips.',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: const [
                                    _HeroStat(
                                      value: 'On-device',
                                      label: 'Voice + retrieval',
                                    ),
                                    _HeroStat(
                                      value: 'Private',
                                      label: 'Sensitive prompts stay local',
                                    ),
                                    _HeroStat(
                                      value: 'First-run setup',
                                      label: 'One download before entry',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: AppColors.card.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: _statusAccent.withValues(alpha: 0.18)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      height: 44,
                                      width: 44,
                                      decoration: BoxDecoration(
                                        color: _statusAccent.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        _errorMessage != null
                                            ? Icons.warning_amber_rounded
                                            : _modelsDownloaded
                                                ? Icons.check_circle_outline_rounded
                                                : Icons.download_for_offline_outlined,
                                        color: _statusAccent,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _statusHeadline,
                                            style: theme.textTheme.titleLarge,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _statusBody,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (_downloadStatus.isNotEmpty || _errorMessage != null || _isDownloading) ...[
                                  const SizedBox(height: 18),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceLight.withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: AppColors.divider),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (_downloadStatus.isNotEmpty)
                                          Text(
                                            _downloadStatus,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        if (_isDownloading) ...[
                                          const SizedBox(height: 14),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(999),
                                            child: LinearProgressIndicator(
                                              minHeight: 10,
                                              value: _downloadProgress.progress,
                                              backgroundColor: AppColors.background,
                                              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Text(
                                                '${(_downloadProgress.progress * 100).round()}% complete',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: AppColors.goldLight,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const Spacer(),
                                              Text(
                                                _downloadProgress.modelName ?? 'Preparing files',
                                                style: theme.textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (_errorMessage != null) ...[
                                          const SizedBox(height: 12),
                                          Text(
                                            _errorMessage!,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: AppColors.error,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _isChecking || _isDownloading
                                        ? null
                                        : _modelsDownloaded
                                            ? _continueToApp
                                            : _downloadModels,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.gold,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 18),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (_isChecking || _isDownloading) ...[
                                          SizedBox(
                                            height: 18,
                                            width: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              value: _isDownloading && _downloadProgress.progress > 0
                                                  ? _downloadProgress.progress
                                                  : null,
                                              color: Colors.black,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        Text(_primaryButtonLabel),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'You only need to do this once unless the local model bundle changes.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'What gets enabled',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              SizedBox(
                                width: featureWidth,
                                child: const _FeatureCard(
                                  icon: Icons.mic_none_rounded,
                                  title: 'Voice-first understanding',
                                  subtitle: 'Recognizes spoken Quran questions, verse requests, and recitation prompts directly on the device.',
                                ),
                              ),
                              SizedBox(
                                width: featureWidth,
                                child: const _FeatureCard(
                                  icon: Icons.auto_awesome_outlined,
                                  title: 'Grounded offline guidance',
                                  subtitle: 'Retrieves relevant ayat and local tafsir evidence before generating a response.',
                                ),
                              ),
                              SizedBox(
                                width: featureWidth,
                                child: const _FeatureCard(
                                  icon: Icons.graphic_eq_rounded,
                                  title: 'Spoken responses',
                                  subtitle: 'Returns natural audio replies so the app still feels conversational after setup.',
                                ),
                              ),
                              SizedBox(
                                width: featureWidth,
                                child: const _FeatureCard(
                                  icon: Icons.shield_outlined,
                                  title: 'Local-first privacy',
                                  subtitle: 'Keeps core interaction closer to the device instead of depending on a permanent cloud session.',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BackdropOrb extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _BackdropOrb({
    required this.size,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;

  const _HeroStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.goldLight),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}