import 'package:flutter/material.dart';

import '../../../core/services/smart_reminders_service.dart';
import '../../../core/theme/app_theme.dart';

class SmartRemindersPage extends StatefulWidget {
  const SmartRemindersPage({super.key});

  @override
  State<SmartRemindersPage> createState() => _SmartRemindersPageState();
}

class _SmartRemindersPageState extends State<SmartRemindersPage> {
  final _svc = SmartRemindersService.instance;
  bool _postFajr = false;
  bool _bedtime = false;
  int _bedHour = 22;
  int _bedMinute = 0;

  @override
  void initState() {
    super.initState();
    _postFajr = _svc.postFajrEnabled;
    _bedtime = _svc.bedtimeEnabled;
    _bedHour = _svc.bedtimeHour;
    _bedMinute = _svc.bedtimeMinute;
  }

  Future<void> _togglePostFajr(bool v) async {
    setState(() => _postFajr = v);
    await _svc.setPostFajrEnabled(v);
    if (!mounted) return;
    if (v) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Morning adhkar reminder scheduled for ~15 min after Fajr.')),
      );
    }
  }

  Future<void> _toggleBedtime(bool v) async {
    setState(() => _bedtime = v);
    await _svc.setBedtime(
      enabled: v,
      hour: _bedHour,
      minute: _bedMinute,
    );
  }

  Future<void> _pickBedtime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _bedHour, minute: _bedMinute),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.gold,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _bedHour = picked.hour;
      _bedMinute = picked.minute;
    });
    await _svc.setBedtime(
      enabled: _bedtime,
      hour: _bedHour,
      minute: _bedMinute,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 80;
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      appBar: AppBar(
        title: const Text('Smart Reminders'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
        physics: const BouncingScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.gold08,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.gold20),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.gold, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Gentle reminders based on your daily rhythm. Post-Fajr fires ~15 minutes after Fajr; bedtime fires at your chosen time.',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(label: 'Morning'),
          const SizedBox(height: 8),
          _ReminderCard(
            icon: Icons.wb_sunny_outlined,
            title: 'Morning Adhkar',
            subtitle: '~15 minutes after Fajr',
            enabled: _postFajr,
            onChanged: _togglePostFajr,
          ),
          const SizedBox(height: 18),
          _SectionTitle(label: 'Night'),
          const SizedBox(height: 8),
          _ReminderCard(
            icon: Icons.bedtime_rounded,
            title: 'Before Sleep',
            subtitle: 'Āyat al-Kursī and bedtime duas',
            enabled: _bedtime,
            onChanged: _toggleBedtime,
          ),
          const SizedBox(height: 8),
          if (_bedtime)
            _TimeRow(
              label: 'Bedtime',
              time: TimeOfDay(hour: _bedHour, minute: _bedMinute),
              onPick: _pickBedtime,
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _ReminderCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: enabled ? AppColors.gold25 : AppColors.dividerAlpha60),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.gold10,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold20),
            ),
            child: Icon(icon, color: AppColors.gold, size: 22),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style:
                      const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeThumbColor: AppColors.gold,
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onPick;
  const _TimeRow({
    required this.label,
    required this.time,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final h = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    final formatted =
        '${h.toString()}:${time.minute.toString().padLeft(2, "0")} $period';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surfaceLightAlpha55,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.dividerAlpha60),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.access_time_rounded,
                  color: AppColors.textMuted, size: 18),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
              const Spacer(),
              Text(
                formatted,
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
