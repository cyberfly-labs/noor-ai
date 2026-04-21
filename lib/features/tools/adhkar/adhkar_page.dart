import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    // Default to evening after noon.
    if (DateTime.now().hour >= 12) _tab.index = 1;
    _morningProgress = List.filled(morningAdhkar.length, 0);
    _eveningProgress = List.filled(eveningAdhkar.length, 0);
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
          labelColor: AppColors.gold,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'Morning'),
            Tab(text: 'Evening'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _list(morningAdhkar, _morningProgress),
          _list(eveningAdhkar, _eveningProgress),
        ],
      ),
    );
  }

  Widget _list(List<Adhkar> items, List<int> progress) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 80),
      itemCount: items.length,
      itemBuilder: (_, i) => _card(items[i], progress[i], () {
        setState(() {
          if (progress[i] < items[i].count) progress[i] += 1;
        });
        HapticFeedback.lightImpact();
      }, () {
        setState(() => progress[i] = 0);
      }),
    );
  }

  Widget _card(Adhkar d, int current, VoidCallback onTap, VoidCallback onReset) {
    final done = current >= d.count;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: done ? AppColors.success : AppColors.gold15, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(d.title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              if (done)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(d.arabic,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 20,
                  height: 1.9,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(d.transliteration,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                  fontSize: 13)),
          const SizedBox(height: 6),
          Text(d.translation,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13.5, height: 1.5)),
          if (d.reference != null) ...[
            const SizedBox(height: 6),
            Text('— ${d.reference!}',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: current / d.count,
                    minHeight: 6,
                    backgroundColor: AppColors.divider,
                    color: AppColors.gold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$current / ${d.count}',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
              IconButton(
                  onPressed: onReset,
                  iconSize: 18,
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppColors.textMuted)),
              FilledButton(
                onPressed: done ? null : onTap,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      done ? AppColors.divider : AppColors.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                ),
                child: Text(done ? 'Done' : 'Count'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
