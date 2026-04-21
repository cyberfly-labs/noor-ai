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
          Text(
            aligned ? 'Aligned with Qibla' : 'Rotate until the arrow is up',
            style: TextStyle(
              color: aligned ? AppColors.success : AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring rotating with device.
                Transform.rotate(
                  angle: -_deviceHeading * math.pi / 180,
                  child: _CompassFace(),
                ),
                // Qibla pointer (rotates to true qibla relative to device).
                Transform.rotate(
                  angle: rotation * math.pi / 180,
                  child: _QiblaPointer(aligned: aligned),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _infoRow('Qibla bearing', '${qibla.toStringAsFixed(1)}°'),
          const SizedBox(height: 6),
          _infoRow('Heading', '${_deviceHeading.toStringAsFixed(1)}°'),
          if (_position != null) ...[
            const SizedBox(height: 6),
            _infoRow(
              'Location',
              '${_position!.latitude.toStringAsFixed(3)}, '
                  '${_position!.longitude.toStringAsFixed(3)}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$label: ',
              style: const TextStyle(color: AppColors.textMuted)),
          Text(value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              )),
        ],
      );
}

class _CompassFace extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [AppColors.surfaceLight, AppColors.background],
        ),
        border: Border.all(color: AppColors.gold30, width: 1.5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
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
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    entry.$1,
                    style: TextStyle(
                      color: entry.$1 == 'N'
                          ? AppColors.gold
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
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
      width: 280,
      height: 280,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 38),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.navigation_rounded, size: 40, color: color),
              const SizedBox(height: 4),
              Icon(Icons.mosque_rounded, size: 22, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
