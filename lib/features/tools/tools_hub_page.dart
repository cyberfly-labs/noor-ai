import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class ToolsHubPage extends StatelessWidget {
  const ToolsHubPage({super.key});

  static const List<_Section> _sections = [
    _Section(
      title: 'Daily',
      tools: [
        _Tool(
          label: 'Daily Ayah',
          subtitle: 'Verse of the day',
          icon: Icons.auto_stories_rounded,
          route: '/daily-ayah',
        ),
        _Tool(
          label: 'Adhkar',
          subtitle: 'Morning & evening',
          icon: Icons.wb_sunny_outlined,
          route: '/tools/adhkar',
        ),
        _Tool(
          label: 'Duas',
          subtitle: 'Supplications',
          icon: Icons.volunteer_activism_rounded,
          route: '/tools/duas',
        ),
        _Tool(
          label: 'Tasbih',
          subtitle: 'Dhikr counter',
          icon: Icons.fingerprint_rounded,
          route: '/tools/tasbih',
        ),
        _Tool(
          label: 'Smart Reminders',
          subtitle: 'After Fajr & bedtime',
          icon: Icons.notifications_active_rounded,
          route: '/tools/reminders',
        ),
      ],
    ),
    _Section(
      title: 'Worship',
      tools: [
        _Tool(
          label: 'Qibla',
          subtitle: 'Direction to Kaaba',
          icon: Icons.explore_rounded,
          route: '/tools/qibla',
        ),
        _Tool(
          label: 'Prayer Times',
          subtitle: 'Salah schedule',
          icon: Icons.access_time_rounded,
          route: '/tools/prayer-times',
        ),
        _Tool(
          label: 'Salah Tracker',
          subtitle: 'Daily 5 prayers',
          icon: Icons.schedule_rounded,
          route: '/tools/salah',
        ),
        _Tool(
          label: 'Fasting',
          subtitle: 'Track your fasts',
          icon: Icons.nightlight_round,
          route: '/tools/fasting',
        ),
        _Tool(
          label: 'Iftar / Suhoor',
          subtitle: 'Fasting countdown',
          icon: Icons.restaurant_rounded,
          route: '/tools/ramadan',
        ),
        _Tool(
          label: 'Mosques',
          subtitle: 'Find nearby',
          icon: Icons.mosque_rounded,
          route: '/tools/mosques',
        ),
      ],
    ),
    _Section(
      title: 'Learn',
      tools: [
        _Tool(
          label: 'Reading Plan',
          subtitle: 'Quran khatm goal',
          icon: Icons.menu_book_rounded,
          route: '/tools/reading-plan',
        ),
        _Tool(
          label: 'Hifz',
          subtitle: 'Memorization',
          icon: Icons.psychology_alt_rounded,
          route: '/tools/hifz',
        ),
        _Tool(
          label: 'Tajweed',
          subtitle: 'Recitation rules',
          icon: Icons.record_voice_over_rounded,
          route: '/tools/tajweed',
        ),
        _Tool(
          label: 'Juz Index',
          subtitle: '30 paras',
          icon: Icons.bookmarks_rounded,
          route: '/tools/juz',
        ),
        _Tool(
          label: 'Seerah',
          subtitle: 'Life of the Prophet ﷺ',
          icon: Icons.history_edu_rounded,
          route: '/tools/seerah',
        ),
        _Tool(
          label: 'Prophet Stories',
          subtitle: 'Tales from Quran',
          icon: Icons.auto_stories_rounded,
          route: '/tools/stories',
        ),
        _Tool(
          label: 'Quiz',
          subtitle: 'Test your knowledge',
          icon: Icons.quiz_rounded,
          route: '/tools/quiz',
        ),
        _Tool(
          label: '99 Names',
          subtitle: 'Asma ul Husna',
          icon: Icons.auto_awesome_rounded,
          route: '/tools/names',
        ),
        _Tool(
          label: 'Hijri Calendar',
          subtitle: 'Islamic dates',
          icon: Icons.calendar_month_rounded,
          route: '/tools/hijri',
        ),
      ],
    ),
    _Section(
      title: 'Community',
      tools: [
        _Tool(
          label: 'Reflections',
          subtitle: 'Quran Reflect feed',
          icon: Icons.forum_rounded,
          route: '/tools/reflections',
        ),
        _Tool(
          label: 'My Posts',
          subtitle: 'Your reflections',
          icon: Icons.edit_note_rounded,
          route: '/posts',
        ),
        _Tool(
          label: 'Bookmarks',
          subtitle: 'Saved ayahs',
          icon: Icons.bookmark_rounded,
          route: '/bookmarks',
        ),
      ],
    ),
    _Section(
      title: 'Utilities',
      tools: [
        _Tool(
          label: 'Achievements',
          subtitle: 'Badges & progress',
          icon: Icons.emoji_events_rounded,
          route: '/tools/achievements',
        ),
        _Tool(
          label: 'Zakat',
          subtitle: 'Charity calculator',
          icon: Icons.account_balance_wallet_rounded,
          route: '/tools/zakat',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      appBar: AppBar(
        title: const Text('Tools'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            for (var i = 0; i < _sections.length; i++) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, i == 0 ? 4 : 20, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: _SectionHeader(
                      title: _sections[i].title,
                      count: _sections[i].tools.length),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.15,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, j) => _ToolCard(tool: _sections[i].tools[j]),
                    childCount: _sections[i].tools.length,
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.of(context).padding.bottom + 100,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Section {
  final String title;
  final List<_Tool> tools;
  const _Section({required this.title, required this.tools});
}

class _Tool {
  final String label;
  final String subtitle;
  final IconData icon;
  final String route;
  const _Tool({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.route,
  });
}

class _ToolCard extends StatelessWidget {
  final _Tool tool;
  const _ToolCard({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(tool.route),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.gold15, width: 0.8),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.gold10,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gold20),
                ),
                child: Icon(tool.icon, color: AppColors.gold, size: 22),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tool.subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11.5,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
