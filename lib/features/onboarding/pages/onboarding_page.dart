import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/llm_service.dart';
import '../../../core/services/model_manager.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StartupGatePage – unchanged logic
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// OnboardingPage – premium redesign
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  final ModelManager _modelManager = ModelManager.instance;

  StreamSubscription<DownloadProgress>? _progressSubscription;
  bool _isChecking = true;
  bool _isDownloading = false;
  bool _modelsDownloaded = false;
  DownloadProgress _downloadProgress = DownloadProgress.zero();
  String _downloadStatus = '';
  String? _errorMessage;

  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic);

    _checkExistingModels();
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _progressSubscription?.cancel();
    super.dispose();
  }

  // ── Model logic (unchanged) ────────────────────────────────────────

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
      _downloadStatus = 'Downloading models…';
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

      // Kick off the native engine now that models are present.
      unawaited(LlmService.instance.initialize());

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
        _errorMessage = _friendlyDownloadError(error);
      });
    }
  }

  String _friendlyDownloadError(Object error) {
    final message = error.toString();
    if (message.contains('SocketException') ||
        message.contains('Connection') ||
        message.contains('incomplete')) {
      return 'Download was interrupted. Keep the app open while downloading, or tap Download Models again to resume from where it stopped.';
    }
    return message;
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
    if (model == null || file == null) return 'Downloading models… $percent%';
    return '$model · $file · $percent%';
  }

  // ── Derived state ──────────────────────────────────────────────────

  String get _primaryButtonLabel {
    if (_isChecking) return 'Checking device…';
    if (_isDownloading) {
      return 'Downloading ${(_downloadProgress.progress * 100).round()}%';
    }
    if (_modelsDownloaded) return 'Enter Noor AI';
    return 'Download Models';
  }

  Color get _statusAccent {
    if (_errorMessage != null) return AppColors.error;
    if (_modelsDownloaded) return AppColors.success;
    return AppColors.gold;
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF040810),
      body: Stack(
        children: [
          // ── Ambient background ──
          const _AmbientBackground(),

          // ── Main content ──
          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: Column(
                children: [
                  // ── Scrollable body ──
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          SizedBox(height: mq.size.height * 0.04),

                          // ── Glowing crescent emblem ──
                          const _CrescentEmblem(),

                          const SizedBox(height: 36),

                          // ── Title ──
                          Text(
                            'Noor AI',
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                              color: AppColors.goldLight,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Your private Quran companion',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),

                          const SizedBox(height: 40),

                          // ── Feature pills ──
                          const _FeaturePillRow(),

                          const SizedBox(height: 40),

                          // ── Status / download card ──
                          _GlassStatusCard(
                            isChecking: _isChecking,
                            isDownloading: _isDownloading,
                            modelsDownloaded: _modelsDownloaded,
                            downloadProgress: _downloadProgress,
                            downloadStatus: _downloadStatus,
                            errorMessage: _errorMessage,
                            statusAccent: _statusAccent,
                          ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // ── Bottom action bar ──
                  Container(
                    padding: EdgeInsets.fromLTRB(28, 14, 28, mq.padding.bottom + 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF040810).withValues(alpha: 0),
                          const Color(0xFF040810),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: _PrimaryActionButton(
                            label: _primaryButtonLabel,
                            isLoading: _isChecking || _isDownloading,
                            progress: _isDownloading ? _downloadProgress.progress : null,
                            onPressed: _isChecking || _isDownloading
                                ? null
                                : _modelsDownloaded
                                    ? _continueToApp
                                    : _downloadModels,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'One-time setup · Everything stays on your device',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Private widgets
// ═════════════════════════════════════════════════════════════════════════════

/// Full-screen ambient glow with floating orbs.
class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          // Deep vignette gradient
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.35),
                radius: 1.1,
                colors: [Color(0xFF0C1624), Color(0xFF040810)],
              ),
            ),
          ),
          // Gold orb – top right
          Positioned(
            top: -60,
            right: -40,
            child: _orb(260, AppColors.gold, 0.10),
          ),
          // Teal orb – mid left
          Positioned(
            top: 260,
            left: -80,
            child: _orb(200, AppColors.accent, 0.06),
          ),
          // Small gold – bottom center
          Positioned(
            bottom: 60,
            left: 80,
            child: _orb(120, AppColors.goldDark, 0.05),
          ),
        ],
      ),
    );
  }

  static Widget _orb(double size, Color color, double opacity) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// A stylised crescent + star emblem drawn with CustomPaint & layered glows.
class _CrescentEmblem extends StatelessWidget {
  const _CrescentEmblem();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.gold.withValues(alpha: 0.12),
                  AppColors.gold.withValues(alpha: 0.03),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Crescent paint
          CustomPaint(
            size: const Size(90, 90),
            painter: _CrescentPainter(),
          ),
          // Star dot
          Positioned(
            top: 32,
            right: 38,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.goldLight,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.65),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrescentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.goldLight, AppColors.gold, AppColors.goldDark],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.width / 2;
    final inner = size.width * 0.38;
    final offset = size.width * 0.22;

    final path = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: outer));
    final cutout = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx + offset, cy - offset * 0.35), radius: inner));
    final crescent = Path.combine(PathOperation.difference, path, cutout);

    // Glow shadow
    canvas.drawPath(
      crescent.shift(const Offset(0, 2)),
      Paint()
        ..color = AppColors.gold.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawPath(crescent, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A row of compact feature capsules.
class _FeaturePillRow extends StatelessWidget {
  const _FeaturePillRow();

  static const _features = <({IconData icon, String label})>[
    (icon: Icons.mic_none_rounded, label: 'Voice'),
    (icon: Icons.auto_awesome_outlined, label: 'Guidance'),
    (icon: Icons.graphic_eq_rounded, label: 'Speech'),
    (icon: Icons.shield_outlined, label: 'Private'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: _features.map((f) => _pill(f.icon, f.label)).toList(),
    );
  }

  static Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.gold),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted-glass style status card with download progress.
class _GlassStatusCard extends StatelessWidget {
  final bool isChecking;
  final bool isDownloading;
  final bool modelsDownloaded;
  final DownloadProgress downloadProgress;
  final String downloadStatus;
  final String? errorMessage;
  final Color statusAccent;

  const _GlassStatusCard({
    required this.isChecking,
    required this.isDownloading,
    required this.modelsDownloaded,
    required this.downloadProgress,
    required this.downloadStatus,
    required this.errorMessage,
    required this.statusAccent,
  });

  String get _headline {
    if (isChecking) return 'Checking device…';
    if (isDownloading) return 'Preparing your companion';
    if (modelsDownloaded) return 'Everything is ready';
    return 'One-time setup';
  }

  String get _body {
    if (isChecking) return 'Verifying voice, search, and response models.';
    if (isDownloading) {
      return 'Downloading on-device models for speech, search, and spoken responses.';
    }
    if (modelsDownloaded) return 'All models are present. Tap below to continue.';
    return 'Download the local models once — after that, Quran guidance, semantic search, and speech all work without the cloud.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: statusAccent.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon + headline
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      errorMessage != null
                          ? Icons.warning_amber_rounded
                          : modelsDownloaded
                              ? Icons.check_circle_outline_rounded
                              : Icons.downloading_rounded,
                      color: statusAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _headline,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),

              // Progress bar region
              if (isDownloading || downloadStatus.isNotEmpty || errorMessage != null) ...[
                const SizedBox(height: 18),
                if (isDownloading) ...[
                  // Thin gold progress track
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: downloadProgress.progress,
                      backgroundColor: AppColors.background.withValues(alpha: 0.6),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${(downloadProgress.progress * 100).round()}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.goldLight,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          downloadProgress.modelName ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A high-contrast CTA button with optional inline spinner.
class _PrimaryActionButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final double? progress;
  final VoidCallback? onPressed;

  const _PrimaryActionButton({
    required this.label,
    required this.isLoading,
    required this.progress,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: onPressed != null ? AppColors.goldGradient : null,
        color: onPressed == null ? AppColors.surfaceLight : null,
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading) ...[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      value: progress != null && progress! > 0 ? progress : null,
                      color: onPressed != null ? Colors.black : AppColors.gold,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: onPressed != null ? Colors.black : AppColors.textMuted,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}