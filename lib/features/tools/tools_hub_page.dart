import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class ToolsHubPage extends StatefulWidget {
  const ToolsHubPage({super.key});

  @override
  State<ToolsHubPage> createState() => _ToolsHubPageState();
}

class _ToolsHubPageState extends State<ToolsHubPage> {
  final _searchController = TextEditingController();
  String _query = '';

  static const List<_Section> _sections = [
    _Section(
      title: 'Daily',
      icon: Icons.wb_sunny_rounded,
      tools: [
        _Tool(
          label: 'Daily Ayah',
          subtitle: 'Verse of the day',
          icon: Icons.auto_stories_rounded,
          route: '/daily-ayah',
          featured: true,
        ),
        _Tool(
          label: 'Adhkar',
          subtitle: 'Morning & evening',
          icon: Icons.wb_sunny_outlined,
          route: '/tools/adhkar',
          featured: true,
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
          featured: true,
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
      icon: Icons.mosque_rounded,
      tools: [
        _Tool(
          label: 'Qibla',
          subtitle: 'Direction to Kaaba',
          icon: Icons.explore_rounded,
          route: '/tools/qibla',
          featured: true,
        ),
        _Tool(
          label: 'Prayer Times',
          subtitle: 'Salah schedule',
          icon: Icons.access_time_rounded,
          route: '/tools/prayer-times',
          featured: true,
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
      icon: Icons.school_rounded,
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
          featured: true,
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
      icon: Icons.people_rounded,
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
      icon: Icons.build_rounded,
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

  List<_Tool> get _allTools =>
      _sections.expand((s) => s.tools).toList(growable: false);

  List<_Tool> get _featuredTools =>
      _allTools.where((t) => t.featured).toList(growable: false);

  List<_Tool> get _filteredTools {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) return const [];
    return _allTools
        .where(
          (t) =>
              t.label.toLowerCase().contains(q) ||
              t.subtitle.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _query.isNotEmpty;
    final filtered = _filteredTools;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header ──────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Tools',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold08,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.gold15),
                          ),
                          child: Text(
                            '${_allTools.length} tools',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // ── Search bar ───────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search tools...',
                          hintStyle: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 14, right: 8),
                            child: Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: AppColors.textMuted,
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 0,
                            minHeight: 0,
                          ),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: AppColors.textMuted,
                                  ),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 0,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Search results ───────────────────────────
            if (isSearching) ...[
              if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 60,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 40,
                          color: AppColors.textMuted.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No tools found for "$_query"',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                      (_, j) => _ToolCard(tool: filtered[j]),
                      childCount: filtered.length,
                    ),
                  ),
                ),
              ],
            ] else ...[
              // ── Featured row ─────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 14,
                        decoration: BoxDecoration(
                          gradient: AppColors.goldGradient,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Featured',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _featuredTools.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) =>
                        _FeaturedToolChip(tool: _featuredTools[i]),
                  ),
                ),
              ),

              // ── Sections ─────────────────────────────
              for (var i = 0; i < _sections.length; i++) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, i == 0 ? 20 : 24, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: _sections[i].title,
                      icon: _sections[i].icon,
                      count: _sections[i].tools.length,
                    ),
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
  final IconData icon;
  final int count;
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.gold08,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: AppColors.gold65),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _Section {
  final String title;
  final IconData icon;
  final List<_Tool> tools;
  const _Section({
    required this.title,
    required this.icon,
    required this.tools,
  });
}

class _Tool {
  final String label;
  final String subtitle;
  final IconData icon;
  final String route;
  final bool featured;
  const _Tool({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.route,
    this.featured = false,
  });
}

class _FeaturedToolChip extends StatelessWidget {
  final _Tool tool;
  const _FeaturedToolChip({required this.tool});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(tool.route),
      child: Container(
        width: 110,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.cardHighlight, AppColors.card],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold20, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.gold12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(tool.icon, color: AppColors.gold, size: 18),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tool.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  tool.subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final _Tool tool;
  const _ToolCard({required this.tool});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Material(
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
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
      ),
    );
  }
}
