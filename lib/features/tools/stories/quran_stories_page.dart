import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'stories_data.dart';

class QuranStoriesPage extends StatelessWidget {
  const QuranStoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 80;
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      appBar: AppBar(
        title: const Text('Stories from the Quran'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
        physics: const BouncingScrollPhysics(),
        itemCount: kProphetStories.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final story = kProphetStories[i];
          return _StoryCard(story: story);
        },
      ),
    );
  }
}

class _StoryCard extends StatefulWidget {
  final ProphetStory story;
  const _StoryCard({required this.story});

  @override
  State<_StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends State<_StoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.story;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.gold15),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.gold10,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.gold25),
                    ),
                    child: const Icon(Icons.auto_stories_rounded,
                        color: AppColors.gold, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.subtitle,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final sr in s.surahs)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.gold10,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.gold20),
                        ),
                        child: Text(
                          sr,
                          style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  s.body,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
