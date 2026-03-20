import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../providers/home_provider.dart';

// ── Noor AI palette ──────────────────────────────────────────────────
const Color _kGold = Color(0xFFD4AF37);
const Color _kGoldLight = Color(0xFFF5E6A3);
const Color _kBg = Color(0xFF0A0A0A);

/// Animated voice button with gold glow – Noor AI theme.
class AnimatedVoiceButton extends StatefulWidget {
  final VoiceState state;
  final VoidCallback onTap;
  final double size;

  const AnimatedVoiceButton({
    super.key,
    required this.state,
    required this.onTap,
    this.size = 160,
  });

  @override
  State<AnimatedVoiceButton> createState() => _AnimatedVoiceButtonState();
}

class _AnimatedVoiceButtonState extends State<AnimatedVoiceButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _ringCtrl;
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800))
      ..repeat(reverse: true);
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _spinCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.state != VoiceState.idle;
    final double s = widget.size;

    return SizedBox(
      width: s * 1.7,
      height: s * 1.7,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer animation layer
          _buildAnimationLayer(s),

          // Golden glow behind orb
          if (isActive)
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) {
                final v = _pulseCtrl.value;
                return Container(
                  width: s + 24,
                  height: s + 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _kGold.withValues(alpha: 0.25 + v * 0.15),
                        blurRadius: 52 + v * 28,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: _kGoldLight.withValues(alpha: 0.12 + v * 0.08),
                        blurRadius: 72 + v * 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                );
              },
            ),

          // Main orb button
          GestureDetector(
            onTap: widget.onTap,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) {
                final scale = widget.state == VoiceState.idle
                    ? 1.0 + _pulseCtrl.value * 0.03
                    : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isActive
                          ? SweepGradient(
                              startAngle: 0,
                              endAngle: math.pi * 2,
                              colors: const [
                                _kGold,
                                _kGoldLight,
                                _kGold,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                              transform: GradientRotation(
                                _pulseCtrl.value * math.pi * 2,
                              ),
                            )
                          : RadialGradient(
                              colors: [
                                _kGold.withValues(alpha: 0.10),
                                _kBg,
                              ],
                            ),
                      border: Border.all(
                        color: isActive
                            ? _kGold.withValues(alpha: 0.6)
                            : _kGold.withValues(alpha: 0.2),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isActive
                              ? _kGold.withValues(alpha: 0.3)
                              : _kGold.withValues(alpha: 0.06),
                          blurRadius: 32,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _iconForState(widget.state),
                        size: s * 0.36,
                        color: isActive
                            ? Colors.white
                            : _kGold.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimationLayer(double size) {
    switch (widget.state) {
      case VoiceState.idle:
        return AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => CustomPaint(
            size: Size(size * 1.5, size * 1.5),
            painter: _IdleGlowPainter(progress: _pulseCtrl.value),
          ),
        );
      case VoiceState.listening:
        return AnimatedBuilder(
          animation: _ringCtrl,
          builder: (_, __) => CustomPaint(
            size: Size(size * 1.6, size * 1.6),
            painter: _ListeningRipplePainter(progress: _ringCtrl.value),
          ),
        );
      case VoiceState.processing:
        return AnimatedBuilder(
          animation: _spinCtrl,
          builder: (_, __) => CustomPaint(
            size: Size(size * 1.4, size * 1.4),
            painter: _HaloPainter(progress: _spinCtrl.value),
          ),
        );
      case VoiceState.speaking:
        return AnimatedBuilder(
          animation: _ringCtrl,
          builder: (_, __) => CustomPaint(
            size: Size(size * 1.5, size * 1.5),
            painter: _SpeakingWavePainter(progress: _ringCtrl.value),
          ),
        );
    }
  }

  IconData _iconForState(VoiceState state) {
    switch (state) {
      case VoiceState.idle:
        return Icons.mic_rounded;
      case VoiceState.listening:
        return Icons.hearing_rounded;
      case VoiceState.processing:
        return Icons.auto_awesome_rounded;
      case VoiceState.speaking:
        return Icons.volume_up_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painters — Noor AI gold theme
// ─────────────────────────────────────────────────────────────────────────────

class _IdleGlowPainter extends CustomPainter {
  final double progress;
  _IdleGlowPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final t = (i + 1) / 4;
      final r = maxR * (0.55 + t * 0.35) + progress * 4;
      final alpha = (0.10 - i * 0.025).clamp(0.02, 1.0);
      final paint = Paint()
        ..color = _kGold.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_IdleGlowPainter old) => old.progress != progress;
}

class _ListeningRipplePainter extends CustomPainter {
  final double progress;
  _ListeningRipplePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final r = maxR * (0.45 + phase * 0.5);
      final alpha = ((1.0 - phase) * 0.45).clamp(0.0, 1.0);
      final paint = Paint()
        ..shader = ui.Gradient.sweep(
          center,
          [
            _kGold.withValues(alpha: alpha),
            _kGoldLight.withValues(alpha: alpha * 0.4),
            _kGold.withValues(alpha: alpha),
          ],
          [0.0, 0.5, 1.0],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1.0 - phase * 0.4);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_ListeningRipplePainter old) => old.progress != progress;
}

class _HaloPainter extends CustomPainter {
  final double progress;
  _HaloPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: r);
    final startAngle = progress * 2 * math.pi;

    final paint = Paint()
      ..shader = ui.Gradient.sweep(
        center,
        [
          _kGold.withValues(alpha: 0.8),
          _kGoldLight.withValues(alpha: 0.6),
          _kGold.withValues(alpha: 0.8),
        ],
        [0.0, 0.5, 1.0],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, math.pi * 0.85, false, paint);

    final trail = Paint()
      ..color = _kGoldLight.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle + math.pi, math.pi * 0.4, false, trail);
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.progress != progress;
}

class _SpeakingWavePainter extends CustomPainter {
  final double progress;
  _SpeakingWavePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = size.width / 2 * 0.55;
    const barCount = 28;

    for (int i = 0; i < barCount; i++) {
      final angle = (i / barCount) * 2 * math.pi;
      final wave = math.sin(progress * 2 * math.pi + i * 0.55) * 0.5 + 0.5;
      final len = 8 + wave * 20;
      final start = Offset(
        center.dx + math.cos(angle) * baseR,
        center.dy + math.sin(angle) * baseR,
      );
      final end = Offset(
        center.dx + math.cos(angle) * (baseR + len),
        center.dy + math.sin(angle) * (baseR + len),
      );
      final t = i / barCount;
      final c = Color.lerp(_kGold, _kGoldLight, t)!;
      final alpha = (0.25 + wave * 0.5).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = c.withValues(alpha: alpha)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(_SpeakingWavePainter old) => old.progress != progress;
}
