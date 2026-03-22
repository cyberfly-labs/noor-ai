import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

class NoorAiApp extends StatefulWidget {
  const NoorAiApp({super.key});

  @override
  State<NoorAiApp> createState() => _NoorAiAppState();
}

class _NoorAiAppState extends State<NoorAiApp> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _widgetLinkSubscription;
  String? _lastHandledWidgetLink;
  DateTime? _lastHandledWidgetLinkAt;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeWidgetLinks());
  }

  @override
  void dispose() {
    _widgetLinkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeWidgetLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      _handleWidgetLink(initial);
    } catch (_) {
      // Ignore malformed initial widget links.
    }

    _widgetLinkSubscription = _appLinks.uriLinkStream.listen(
      _handleWidgetLink,
      onError: (_) {
        // Ignore malformed runtime widget links.
      },
    );
  }

  void _handleWidgetLink(Uri? uri) {
    if (uri == null) {
      return;
    }

    if (uri.scheme != 'noorai' || uri.host != 'daily-ayah') {
      return;
    }

    final serialized = uri.toString();
    final now = DateTime.now();
    if (_lastHandledWidgetLink == serialized &&
        _lastHandledWidgetLinkAt != null &&
        now.difference(_lastHandledWidgetLinkAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastHandledWidgetLink = serialized;
    _lastHandledWidgetLinkAt = now;

    final query = <String, String>{};
    if (uri.path == '/explain') {
      query['explain'] = '1';
    }
    if (uri.path == '/refresh') {
      query['refresh'] = '1';
    }
    final verseKey = uri.queryParameters['verseKey'];
    if (verseKey != null && verseKey.trim().isNotEmpty) {
      query['verseKey'] = verseKey.trim();
    }
    final requestId = uri.queryParameters['requestId'];
    if (requestId != null && requestId.trim().isNotEmpty) {
      query['requestId'] = requestId.trim();
    }

    final target = Uri(path: '/daily-ayah', queryParameters: query).toString();
    appRouter.go(target);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Noor AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
    );
  }
}
