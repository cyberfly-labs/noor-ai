import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';

class MosqueFinderPage extends StatefulWidget {
  const MosqueFinderPage({super.key});

  @override
  State<MosqueFinderPage> createState() => _MosqueFinderPageState();
}

class _MosqueFinderPageState extends State<MosqueFinderPage> {
  Position? _pos;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await LocationService.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _pos = p;
      _loading = false;
      _error = p == null
          ? 'Location unavailable. You can still search with the buttons below.'
          : null;
    });
  }

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Mosque Finder')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(
                      child: CircularProgressIndicator(color: AppColors.gold)),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppColors.cardGradient,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.gold15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.mosque_rounded, color: AppColors.gold),
                          SizedBox(width: 10),
                          Text('Find nearby mosques',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _pos == null
                            ? _error ??
                                'Grant location for precise results.'
                            : 'Located at ${_pos!.latitude.toStringAsFixed(3)}, '
                                '${_pos!.longitude.toStringAsFixed(3)}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              _button(
                icon: Icons.map_rounded,
                label: 'Open in Google Maps',
                onTap: () {
                  final q = _pos == null
                      ? 'mosque near me'
                      : 'mosque';
                  final u = _pos == null
                      ? Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}')
                      : Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}&ll=${_pos!.latitude},${_pos!.longitude}');
                  _open(u);
                },
              ),
              const SizedBox(height: 10),
              _button(
                icon: Icons.apple,
                label: 'Open in Apple Maps',
                onTap: () {
                  final u = _pos == null
                      ? Uri.parse(
                          'https://maps.apple.com/?q=mosque%20near%20me')
                      : Uri.parse(
                          'https://maps.apple.com/?q=mosque&sll=${_pos!.latitude},${_pos!.longitude}');
                  _open(u);
                },
              ),
              const SizedBox(height: 10),
              _button(
                icon: Icons.language_rounded,
                label: 'Search on OpenStreetMap',
                onTap: () {
                  final u = _pos == null
                      ? Uri.parse(
                          'https://www.openstreetmap.org/search?query=mosque')
                      : Uri.parse(
                          'https://www.openstreetmap.org/search?query=mosque#map=14/${_pos!.latitude}/${_pos!.longitude}');
                  _open(u);
                },
              ),
              const SizedBox(height: 10),
              _button(
                icon: Icons.refresh_rounded,
                label: 'Refresh location',
                onTap: () {
                  setState(() => _loading = true);
                  _load();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold15),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.gold),
        title: Text(label,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.textMuted),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
