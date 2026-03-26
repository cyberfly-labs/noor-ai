import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/bookmarks/pages/bookmarks_page.dart';
import '../../features/chat/pages/chat_history_page.dart';
import '../../features/posts/pages/posts_feed_page.dart';
import '../../features/daily_ayah/pages/daily_ayah_page.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/onboarding/pages/onboarding_page.dart';
import '../../features/quran/pages/quran_page.dart';
import '../../features/quran/pages/surah_detail_page.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../features/shell/shell_page.dart';
import '../../features/verse/pages/verse_detail_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const StartupGatePage(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingPage(),
    ),
    GoRoute(
      path: '/verse/:surah/:ayah',
      builder: (context, state) {
        final surah = int.tryParse(state.pathParameters['surah'] ?? '');
        final ayah = int.tryParse(state.pathParameters['ayah'] ?? '');

        return VerseDetailPage(
          surahNumber: surah ?? 1,
          ayahNumber: ayah ?? 1,
        );
      },
    ),
    ShellRoute(
      builder: (context, state, child) => ShellPage(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomePage(),
          ),
        ),
        GoRoute(
          path: '/quran',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: QuranPage(),
          ),
          routes: [
            GoRoute(
              path: 'surah/:surah',
              builder: (context, state) {
                final surah = int.tryParse(state.pathParameters['surah'] ?? '');

                return SurahDetailPage(
                  surahNumber: surah ?? 1,
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/chat',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ChatHistoryPage(),
          ),
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
          pageBuilder: (context, state) => const NoTransitionPage(
            child: BookmarksPage(),
          ),
        ),
        GoRoute(
          path: '/posts',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: PostsFeedPage(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsPage(),
          ),
        ),
      ],
    ),
  ],
);
