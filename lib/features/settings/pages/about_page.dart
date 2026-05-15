import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

/// About / Hackathon submission showcase page.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('About Noor AI'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).padding.bottom + 40,
          ),
          children: [
            // ── Hero card ──────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.cardHighlight,
                    AppColors.card,
                    AppColors.gold04,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.gold20, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.gold12,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.gold25),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.gold,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Noor AI',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Quran Foundation Hackathon 2026',
                            style: TextStyle(
                              color: AppColors.gold65,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'An offline-first AI Quran companion that deepens your connection with the Quran through voice, semantic search, and community reflection.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── API integrations ───────────────────────
            _SectionHeader(label: 'Quran Foundation API Integrations'),
            const SizedBox(height: 12),

            _ApiCard(
              category: 'Content APIs',
              icon: Icons.menu_book_rounded,
              items: const [
                'Quran API — verses, surahs, juzs, search',
                'Audio API — recitations with QF + fallback',
                'Tafsir API — verse explanations (bundled)',
                'Translation API — multiple translation resources',
                'Post API — community reflections feed',
              ],
            ),
            const SizedBox(height: 10),
            _ApiCard(
              category: 'User APIs',
              icon: Icons.person_rounded,
              items: const [
                'Bookmarks — save & sync verses (bidirectional)',
                'Streak Tracking — Quran reading streaks',
                'Post API — publish reflections to QuranReflect',
                'Activity & Goals — reading sessions & activity days',
                'Reading Sessions — track surah reading progress',
              ],
            ),

            const SizedBox(height: 24),

            // ── Key features ───────────────────────────
            _SectionHeader(label: 'Key Features'),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _FeaturePill(
                  icon: Icons.mic_rounded,
                  label: 'Voice AI',
                ),
                _FeaturePill(
                  icon: Icons.search_rounded,
                  label: 'Semantic Search',
                ),
                _FeaturePill(
                  icon: Icons.auto_awesome_rounded,
                  label: 'On-Device LLM',
                ),
                _FeaturePill(
                  icon: Icons.bookmark_rounded,
                  label: 'Bookmarks Sync',
                ),
                _FeaturePill(
                  icon: Icons.local_fire_department_rounded,
                  label: 'Streak Tracking',
                ),
                _FeaturePill(
                  icon: Icons.edit_note_rounded,
                  label: 'Reflections',
                ),
                _FeaturePill(
                  icon: Icons.collections_bookmark_rounded,
                  label: 'Collections',
                ),
                _FeaturePill(
                  icon: Icons.explore_rounded,
                  label: 'Qibla Compass',
                ),
                _FeaturePill(
                  icon: Icons.access_time_rounded,
                  label: 'Prayer Times',
                ),
                _FeaturePill(
                  icon: Icons.fingerprint_rounded,
                  label: 'Tasbih Counter',
                ),
                _FeaturePill(
                  icon: Icons.quiz_rounded,
                  label: 'Islamic Quiz',
                ),
                _FeaturePill(
                  icon: Icons.emoji_events_rounded,
                  label: 'Achievements',
                ),
                _FeaturePill(
                  icon: Icons.shield_outlined,
                  label: 'Offline-First',
                ),
                _FeaturePill(
                  icon: Icons.notifications_active_rounded,
                  label: 'Smart Reminders',
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Judging criteria ───────────────────────
            _SectionHeader(label: 'Judging Criteria Coverage'),
            const SizedBox(height: 12),

            _CriteriaCard(
              label: 'Impact on Quran Engagement',
              points: 30,
              description:
                  'Daily Ayah, streaks, reading plans, reflections, AI-powered guidance, and 20+ Islamic tools all drive lasting engagement.',
            ),
            const SizedBox(height: 8),
            _CriteriaCard(
              label: 'Product Quality & UX',
              points: 20,
              description:
                  'Polished dark-mode UI with gold accents, smooth animations, consistent design system, and accessible touch targets.',
            ),
            const SizedBox(height: 8),
            _CriteriaCard(
              label: 'Technical Execution',
              points: 20,
              description:
                  'OAuth2 PKCE auth, bidirectional sync, on-device LLM + RAG, vector search, offline-first architecture.',
            ),
            const SizedBox(height: 8),
            _CriteriaCard(
              label: 'Innovation & Creativity',
              points: 15,
              description:
                  'First Quran app with on-device voice AI + semantic RAG search. Emotional verse selector, AI-powered explanations.',
            ),
            const SizedBox(height: 8),
            _CriteriaCard(
              label: 'Effective Use of APIs',
              points: 15,
              description:
                  'Deep integration of all Content + User APIs: bookmarks, streaks, activity, reading sessions, posts, reflections feed.',
            ),

            const SizedBox(height: 24),

            // ── Tech stack ─────────────────────────────
            _SectionHeader(label: 'Tech Stack'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.divider, width: 0.5),
              ),
              child: const Column(
                children: [
                  _TechRow(label: 'Framework', value: 'Flutter (Dart)'),
                  _TechRow(label: 'State Management', value: 'Riverpod'),
                  _TechRow(label: 'AI Engine', value: 'MNN + Qwen3.5 (on-device)'),
                  _TechRow(label: 'Speech', value: 'Whisper (on-device ASR)'),
                  _TechRow(label: 'Vector Search', value: 'zvec_flutter (local)'),
                  _TechRow(label: 'Auth', value: 'OAuth2 PKCE (QF)'),
                  _TechRow(label: 'Storage', value: 'SQLite + SharedPrefs'),
                  _TechRow(label: 'Routing', value: 'GoRouter'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Links ──────────────────────────────────
            _SectionHeader(label: 'Submission'),
            const SizedBox(height: 12),
            _LinkButton(
              icon: Icons.language_rounded,
              label: 'Quran Foundation Hackathon',
              url: 'https://launch.provisioncapital.com/quran-hackathon',
            ),
            const SizedBox(height: 8),
            _LinkButton(
              icon: Icons.api_rounded,
              label: 'Quran Foundation API Docs',
              url: 'https://api-docs.quran.foundation',
            ),

            const SizedBox(height: 32),
            const Center(
              child: Text(
                '﷽',
                style: TextStyle(color: AppColors.gold40, fontSize: 24),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                'Built with devotion for the Quran Foundation Hackathon 2026',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ApiCard extends StatelessWidget {
  final String category;
  final IconData icon;
  final List<String> items;

  const _ApiCard({
    required this.category,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.gold),
              const SizedBox(width: 8),
              Text(
                category,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.gold08,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold15, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.gold65),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CriteriaCard extends StatelessWidget {
  final String label;
  final int points;
  final String description;

  const _CriteriaCard({
    required this.label,
    required this.points,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '$points',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.45,
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

class _TechRow extends StatelessWidget {
  final String label;
  final String value;

  const _TechRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;

  const _LinkButton({
    required this.icon,
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.gold65),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
