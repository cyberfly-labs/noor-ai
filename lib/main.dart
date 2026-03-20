import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/database_service.dart';
import 'core/services/llm_service.dart';
import 'core/services/model_manager.dart';
import 'core/services/quran_user_session_service.dart';
import 'core/services/vector_store_service.dart' show VectorStoreService, kEmotionalVerses;
import 'core/services/voice_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Dark status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A0A),
  ));

  runApp(const ProviderScope(child: NoorAiApp()));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_warmUpCoreServices());
  });
}

Future<void> _warmUpCoreServices() async {
  VectorStoreService.instance.seedEmotionalVerses(kEmotionalVerses);

  unawaited(_runStartupTask(
    'database init',
    () async => DatabaseService.instance.database,
  ));
  unawaited(_runStartupTask(
    'Quran user session init',
    () => QuranUserSessionService.instance.initialize().timeout(
      const Duration(seconds: 5),
    ),
  ));
  unawaited(_runStartupTask(
    'model manager init',
    () => ModelManager.instance.initialize().timeout(
      const Duration(seconds: 5),
    ),
  ));
  unawaited(_runStartupTask('LLM prewarm', LlmService.instance.initialize));
  unawaited(_runStartupTask('ASR prewarm', VoiceService.instance.initAsr));
}

Future<void> _runStartupTask(
  String label,
  Future<Object?> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    debugPrint('Startup: $label skipped: $error');
  }
}
