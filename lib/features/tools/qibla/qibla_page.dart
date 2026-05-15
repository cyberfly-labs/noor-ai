import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';

/// Kaaba coordinates (Masjid al-Haram, Mecca).
const double _kaabaLat = 21.4225241;
const double _kaabaLng = 39.8261818;

class QiblaPage extends StatefulWidget {
  const QiblaPage({super.key});

  @override
  State<QiblaPage> createState() => _QiblaPageState();
}

class _QiblaPageState extends State<QiblaPage> {
  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<AccelerometerEvent>? _accSub;

  double? _qiblaBearing; // degrees from true north to qibla
  double _deviceHeading = 0; // degrees from north, device
  Position? _position;
  String? _error;
  bool _loading = true;

  // Last accelerometer reading for tilt compensation.
  double _ax = 0, _ay = 0, _az = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;

    if (pos == null) {
      setState(() {
        _loading = false;
        _error = 'Location unavailable. Grant location permission to compute '
            'the Qibla direction.';
      });
      return;
    }

    final bearing = _qiblaDirection(pos.latitude, pos.longitude);
    setState(() {
      _position = pos;
      _qiblaBearing = bearing;
      _loading = false;
    });

    _accSub = accelerometerEventStream().listen((e) {
      _ax = e.x;
      _ay = e.y;
      _az = e.z;
    });
    _magSub = magnetometerEventStream().listen(_onMag);
  }

  void _onMag(MagnetometerEvent e) {
    // Tilt-compensated compass using accelerometer + magnetometer.
    final ax = _ax, ay = _ay, az = _az;
    final norm = math.sqrt(ax * ax + ay * ay + az * az);
    if (norm == 0) return;

    final pitch = math.asin(-ax / norm);
    final roll = math.asin(ay / math.sqrt(ay * ay + az * az));

    final mx = e.x * math.cos(pitch) +
        e.z * math.sin(pitch);
    final my = e.x * math.sin(roll) * math.sin(pitch) +
        e.y * math.cos(roll) -
        e.z * math.sin(roll) * math.cos(pitch);

    var heading = math.atan2(-my, mx) * 180 / math.pi;
    if (heading < 0) heading += 360;

    if (!mounted) return;
    setState(() => _deviceHeading = heading);
  }

  /// Great-circle initial bearing from (lat,lng) to Kaaba, in degrees.
  double _qiblaDirection(double lat, double lng) {
    final phi1 = lat * math.pi / 180;
    final phi2 = _kaabaLat * math.pi / 180;
    final deltaLambda = (_kaabaLng - lng) * math.pi / 180;

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);

    var theta = math.atan2(y, x) * 180 / math.pi;
    theta = (theta + 360) % 360;
    return theta;
  }

  @override
  void dispose() {
    _magSub?.cancel();
    _accSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qibla = _qiblaBearing;
    final rotationToQibla = qibla == null ? 0.0 : (qibla - _deviceHeading);
    final aligned =
        qibla != null && (rotationToQibla.abs() % 360 < 5 ||
            (360 - (rotationToQibla.abs() % 360)) < 5);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Qibla')),
      body: SafeArea(
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(color: AppColors.gold)
              : _error != null
                  ? _buildError(_error!)
                  : _buildCompass(qibla!, rotationToQibla, aligned),
        ),
      ),
    );
  }

  Widget _buildError(String message) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_rounded,
                color: AppColors.gold, size: 56),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _init();
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      );

  Widget _buildCompass(double qibla, double rotation, bool aligned) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Status badge
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: aligned
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.gold10,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: aligned
                    ? AppColors.success.withValues(alpha: 0.3)
                    : AppColors.gold20,
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  aligned
                      ? Icons.check_circle_rounded
                      : Icons.rotate_right_rounded,
                  size: 16,
                  color: aligned ? AppColors.success : AppColors.gold,
                ),
                const SizedBox(width: 6),
                Text(
                  aligned
                      ? 'Facing Qibla'
                      : 'Rotate until the arrow points up',
                  style: TextStyle(
                    color: aligned ? AppColors.success : AppColors.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Compass
          SizedBox(
            width: 290,
            height: 290,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow
                Container(
                  width: 290,
                  height: 290,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (aligned ? AppColors.success : AppColors.gold)
                            .withValues(alpha: 0.08),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
                // Compass face rotating with device
                Transform.rotate(
                  angle: -_deviceHeading * math.pi / 180,
                  child: _CompassFace(),
                ),
                // Qibla pointer
                Transform.rotate(
                  angle: rotation * math.pi / 180,
                  child: _QiblaPointer(aligned: aligned),
                ),
                // Center dot
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: aligned ? AppColors.success : AppColors.gold,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (aligned ? AppColors.success : AppColors.gold)
                            .withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Info cards
          Row(
            children: [
              Expanded(
                child: _infoCard(
                  'Qibla',
                  '${qibla.toStringAsFixed(1)}°',
                  Icons.explore_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _infoCard(
                  'Heading',
                  '${_deviceHeading.toStringAsFixed(1)}°',
                  Icons.navigation_rounded,
                ),
              ),
            ],
          ),
          if (_position != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider, width: 0.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_position!.latitude.toStringAsFixed(4)}, '
                    '${_position!.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.gold65),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompassFace extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [AppColors.cardHighlight, AppColors.background],
          stops: [0.0, 1.0],
        ),
        border: Border.all(color: AppColors.gold25, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.black18,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Tick marks
          for (int i = 0; i < 36; i++)
            Transform.rotate(
              angle: i * 10 * math.pi / 180,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: i % 9 == 0 ? 2 : 1,
                  height: i % 9 == 0 ? 12 : 6,
                  color: i % 9 == 0
                      ? AppColors.gold40
                      : AppColors.textMuted.withValues(alpha: 0.2),
                ),
              ),
            ),
          // Cardinal labels
          for (final entry in const [
            ('N', 0.0),
            ('E', 90.0),
            ('S', 180.0),
            ('W', 270.0),
          ])
            Transform.rotate(
              angle: entry.$2 * math.pi / 180,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    entry.$1,
                    style: TextStyle(
                      color: entry.$1 == 'N'
                          ? AppColors.gold
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QiblaPointer extends StatelessWidget {
  final bool aligned;
  const _QiblaPointer({required this.aligned});

  @override
  Widget build(BuildContext context) {
    final color = aligned ? AppColors.success : AppColors.gold;
    return SizedBox(
      width: 290,
      height: 290,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(Icons.navigation_rounded, size: 44, color: color),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.mosque_rounded, size: 18, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
