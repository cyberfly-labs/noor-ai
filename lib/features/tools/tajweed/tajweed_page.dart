import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'tajweed_data.dart';

class TajweedPage extends StatelessWidget {
  const TajweedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 80;
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      appBar: AppBar(
        title: const Text('Tajweed Rules'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
        physics: const BouncingScrollPhysics(),
        itemCount: kTajweedGroups.length,
        itemBuilder: (context, gi) {
          final group = kTajweedGroups[gi];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(4, gi == 0 ? 0 : 16, 0, 10),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        group.category,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final rule in group.rules) ...[
                _RuleCard(rule: rule),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final TajweedRule rule;
  const _RuleCard({required this.rule});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rule.arabic,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 18,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            rule.description,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in rule.letters)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.gold10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.gold20),
                  ),
                  child: Text(
                    l,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 14,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLightAlpha55,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.dividerAlpha60),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  rule.example,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    height: 1.6,
                    fontFamily: 'UthmanicHafs',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rule.exampleRef,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
