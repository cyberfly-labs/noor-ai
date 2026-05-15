import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import 'adhkar_data.dart';

class AdhkarPage extends StatefulWidget {
  const AdhkarPage({super.key});

  @override
  State<AdhkarPage> createState() => _AdhkarPageState();
}

class _AdhkarPageState extends State<AdhkarPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late List<int> _morningProgress;
  late List<int> _eveningProgress;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    if (DateTime.now().hour >= 12) _tab.index = 1;
    _morningProgress = List.filled(morningAdhkar.length, 0);
    _eveningProgress = List.filled(eveningAdhkar.length, 0);
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      for (int i = 0; i < morningAdhkar.length; i++) {
        _morningProgress[i] = p.getInt('adhkar.morning.$i') ?? 0;
      }
      for (int i = 0; i < eveningAdhkar.length; i++) {
        _eveningProgress[i] = p.getInt('adhkar.evening.$i') ?? 0;
      }
    });
  }

  Future<void> _saveProgress(bool isMorning, int index, int value) async {
    final key = isMorning ? 'adhkar.morning.$index' : 'adhkar.evening.$index';
    await _prefs?.setInt(key, value);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Adhkar'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.gold,
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: AppColors.gold,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Morning'),
            Tab(text: 'Evening'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _list(morningAdhkar, _morningProgress, isMorning: true),
          _list(eveningAdhkar, _eveningProgress, isMorning: false),
        ],
      ),
    );
  }

  Widget _list(List<Adhkar> items, List<int> progress, {required bool isMorning}) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 80),
      itemCount: items.length,
      itemBuilder: (_, i) => _card(items[i], progress[i], () {
        if (progress[i] < items[i].count) {
          setState(() => progress[i] += 1);
          _saveProgress(isMorning, i, progress[i]);
          HapticFeedback.lightImpact();
        }
      }, () {
        setState(() => progress[i] = 0);
        _saveProgress(isMorning, i, 0);
      }),
    );
  }

  Widget _card(Adhkar d, int current, VoidCallback onTap, VoidCallback onReset) {
    final done = current >= d.count;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: done ? AppColors.success : AppColors.gold15,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (done)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_rounded,
                        color: AppColors.success,
                        size: 13,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Done',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              d.arabic,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 22,
                height: 1.9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            d.transliteration,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            d.translation,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
          if (d.reference != null) ...[
            const SizedBox(height: 6),
            Text(
              '— ${d.reference!}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: current / d.count,
              minHeight: 5,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(
                done ? AppColors.success : AppColors.gold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$current / ${d.count}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onReset,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.divider,
                      width: 0.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: done ? null : onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: done ? null : AppColors.goldGradient,
                    color: done ? AppColors.divider : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    done ? 'Done' : 'Count',
                    style: TextStyle(
                      color: done ? AppColors.textMuted : Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
