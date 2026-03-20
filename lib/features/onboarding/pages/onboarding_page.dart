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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Text(
              'Noor AI',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Download the on-device Quran, voice, and AI models before entering the app.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 24),
            _FeatureCard(
              title: 'Voice Understanding',
              subtitle: 'Speech recognition for Quran questions and recitation prompts',
            ),
            _FeatureCard(
              title: 'Offline Guidance',
              subtitle: 'On-device explanation and semantic retrieval',
            ),
            _FeatureCard(
              title: 'Spoken Responses',
              subtitle: 'Natural audio replies without network dependency',
            ),
            const SizedBox(height: 24),
            if (_isChecking)
              const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              )
            else ...[
              if (_downloadStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _downloadStatus,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      if (_isDownloading) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            value: _downloadProgress.progress,
                            backgroundColor: AppColors.card,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.gold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_downloadProgress.progress * 100).round()}% complete',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isDownloading
                      ? null
                      : _modelsDownloaded
                          ? _continueToApp
                          : _downloadModels,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isDownloading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: _downloadProgress.progress > 0
                                    ? _downloadProgress.progress
                                    : null,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Downloading ${(_downloadProgress.progress * 100).round()}%',
                            ),
                          ],
                        )
                      : Text(_modelsDownloaded ? 'Continue' : 'Download Models'),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _FeatureCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.82),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}