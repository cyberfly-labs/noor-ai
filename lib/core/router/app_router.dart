import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/bookmarks/pages/bookmarks_page.dart';
import '../../features/chat/pages/chat_history_page.dart';
import '../../features/daily_ayah/pages/daily_ayah_page.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/login/pages/login_page.dart';
import '../../features/onboarding/pages/onboarding_page.dart';
import '../../features/posts/pages/posts_feed_page.dart';
import '../../features/quran/pages/quran_page.dart';
import '../../features/quran/pages/surah_detail_page.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../features/shell/shell_page.dart';
import '../../features/tools/duas/duas_page.dart';
import '../../features/tools/fasting/fasting_tracker_page.dart';
import '../../features/tools/hifz/hifz_tracker_page.dart';
import '../../features/tools/hijri_calendar/hijri_calendar_page.dart';
import '../../features/tools/iftar/iftar_countdown_page.dart';
import '../../features/tools/juz/juz_index_page.dart';
import '../../features/tools/mosque_finder/mosque_finder_page.dart';
import '../../features/tools/names/names_of_allah_page.dart';
import '../../features/tools/prayer_times/prayer_times_page.dart';
import '../../features/tools/qibla/qibla_page.dart';
import '../../features/tools/adhkar/adhkar_page.dart';
import '../../features/tools/reading_plan/reading_plan_page.dart';
import '../../features/tools/reflections/reflections_feed_page.dart';
import '../../features/tools/salah/salah_tracker_page.dart';
import '../../features/tools/seerah/seerah_page.dart';
import '../../features/tools/tasbih/tasbih_page.dart';
import '../../features/tools/tools_hub_page.dart';
import '../../features/tools/zakat/zakat_page.dart';
import '../../features/tools/achievements/achievements_page.dart';
import '../../features/tools/quizzes/islamic_quiz_page.dart';
import '../../features/tools/reminders/smart_reminders_page.dart';
import '../../features/tools/stories/quran_stories_page.dart';
import '../../features/tools/tajweed/tajweed_page.dart';
import '../../features/verse/pages/verse_detail_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const StartupGatePage()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingPage(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/verse/:surah/:ayah',
      builder: (context, state) {
        final surah = int.tryParse(state.pathParameters['surah'] ?? '');
        final ayah = int.tryParse(state.pathParameters['ayah'] ?? '');

        return VerseDetailPage(surahNumber: surah ?? 1, ayahNumber: ayah ?? 1);
      },
    ),
    ShellRoute(
      builder: (context, state, child) => ShellPage(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomePage()),
        ),
        GoRoute(
          path: '/quran',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: QuranPage()),
          routes: [
            GoRoute(
              path: 'surah/:surah',
              builder: (context, state) {
                final surah = int.tryParse(state.pathParameters['surah'] ?? '');

                return SurahDetailPage(surahNumber: surah ?? 1);
              },
            ),
          ],
        ),
        GoRoute(
          path: '/chat',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ChatHistoryPage()),
        ),
        GoRoute(
          path: '/daily-ayah',
          pageBuilder: (context, state) => NoTransitionPage(
            child: DailyAyahPage(
              autoExplain: state.uri.queryParameters['explain'] == '1',
              forceRefresh: state.uri.queryParameters['refresh'] == '1',
              refreshRequestId: state.uri.queryParameters['requestId'],
              requestedVerseKey: state.uri.queryParameters['verseKey'],
            ),
          ),
        ),
        GoRoute(
          path: '/bookmarks',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: BookmarksPage()),
        ),
        GoRoute(
          path: '/posts',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: PostsFeedPage()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SettingsPage()),
        ),
        GoRoute(
          path: '/tools',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ToolsHubPage()),
          routes: [
            GoRoute(
              path: 'qibla',
              builder: (context, state) => const QiblaPage(),
            ),
            GoRoute(
              path: 'prayer-times',
              builder: (context, state) => const PrayerTimesPage(),
            ),
            GoRoute(
              path: 'tasbih',
              builder: (context, state) => const TasbihPage(),
            ),
            GoRoute(
              path: 'hijri',
              builder: (context, state) => const HijriCalendarPage(),
            ),
            GoRoute(
              path: 'names',
              builder: (context, state) => const NamesOfAllahPage(),
            ),
            GoRoute(
              path: 'duas',
              builder: (context, state) => const DuasPage(),
            ),
            GoRoute(
              path: 'zakat',
              builder: (context, state) => const ZakatPage(),
            ),
            GoRoute(
              path: 'fasting',
              builder: (context, state) => const FastingTrackerPage(),
            ),
            GoRoute(
              path: 'mosques',
              builder: (context, state) => const MosqueFinderPage(),
            ),
            GoRoute(
              path: 'adhkar',
              builder: (context, state) => const AdhkarPage(),
            ),
            GoRoute(
              path: 'salah',
              builder: (context, state) => const SalahTrackerPage(),
            ),
            GoRoute(
              path: 'reading-plan',
              builder: (context, state) => const ReadingPlanPage(),
            ),
            GoRoute(
              path: 'hifz',
              builder: (context, state) => const HifzTrackerPage(),
            ),
            GoRoute(
              path: 'seerah',
              builder: (context, state) => const SeerahPage(),
            ),
            GoRoute(
              path: 'ramadan',
              builder: (context, state) => const IftarCountdownPage(),
            ),
            GoRoute(
              path: 'juz',
              builder: (context, state) => const JuzIndexPage(),
            ),
            GoRoute(
              path: 'reflections',
              builder: (context, state) => const ReflectionsFeedPage(),
            ),
            GoRoute(
              path: 'stories',
              builder: (context, state) => const QuranStoriesPage(),
            ),
            GoRoute(
              path: 'quiz',
              builder: (context, state) => const IslamicQuizPage(),
            ),
            GoRoute(
              path: 'tajweed',
              builder: (context, state) => const TajweedPage(),
            ),
            GoRoute(
              path: 'achievements',
              builder: (context, state) => const AchievementsPage(),
            ),
            GoRoute(
              path: 'reminders',
              builder: (context, state) => const SmartRemindersPage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
