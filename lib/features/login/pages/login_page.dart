import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/quran_user_session_service.dart';
import '../../../core/theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final QuranUserSessionService _session = QuranUserSessionService.instance;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeIn;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();

    _session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (_session.isSignedIn) {
      context.go('/home');
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final launched = await _session.startSignIn();

    if (!mounted) return;

    if (!launched) {
      setState(() {
        _busy = false;
        _error = _session.lastAuthError ?? 'Could not open sign-in page.';
      });
    } else {
      // Keep busy until the callback arrives and _onSessionChanged fires.
      // Add a timeout so the UI isn't stuck forever.
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && _busy) {
          setState(() => _busy = false);
        }
      });
    }
  }

  void _skip() {
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF040810),
      body: Stack(
        children: [
          // ── Ambient background ──
          const _AmbientBg(),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          SizedBox(height: mq.size.height * 0.10),

                          // ── Icon ──
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.gold12,
                                  AppColors.gold03,
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.55, 1.0],
                              ),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_outlined,
                              size: 44,
                              color: AppColors.goldLight,
                            ),
                          ),

                          const SizedBox(height: 36),

                          Text(
                            'Welcome to Noor AI',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              color: AppColors.goldLight,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Sign in with your Quran Foundation account to unlock reflections, bookmarks, reading progress, and streak sync.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.6,
                            ),
                          ),

                          const SizedBox(height: 44),

                          // ── Feature list ──
                          _featureRow(Icons.bookmark_border_rounded, 'Sync bookmarks across devices'),
                          const SizedBox(height: 14),
                          _featureRow(Icons.forum_outlined, 'Share reflections on QuranReflect'),
                          const SizedBox(height: 14),
                          _featureRow(Icons.trending_up_rounded, 'Track your reading streak'),
                          const SizedBox(height: 14),
                          _featureRow(Icons.sync_rounded, 'Cloud-backed reading progress'),

                          if (_error != null) ...[
                            const SizedBox(height: 24),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 13,
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // ── Bottom action area ──
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      28, 14, 28, mq.padding.bottom + 14,
                    ),
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
                        // Sign-in button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: _busy ? null : AppColors.goldGradient,
                              color: _busy ? AppColors.surfaceLight : null,
                              boxShadow: _busy
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: AppColors.gold35,
                                        blurRadius: 24,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _busy ? null : _signIn,
                                child: Center(
                                  child: _busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: AppColors.gold,
                                          ),
                                        )
                                      : const Text(
                                          'Sign in with Quran Foundation',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Skip button
                        TextButton(
                          onPressed: _skip,
                          child: Text(
                            'Skip for now',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
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

  Widget _featureRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.gold12,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.gold),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _AmbientBg extends StatelessWidget {
  const _AmbientBg();

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.35),
                radius: 1.1,
                colors: [Color(0xFF0C1624), Color(0xFF040810)],
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: _orb(260, AppColors.gold, 0.10),
          ),
          Positioned(
            top: 260,
            left: -80,
            child: _orb(200, AppColors.accent, 0.06),
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
