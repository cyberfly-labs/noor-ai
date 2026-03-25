import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/database_service.dart';
import 'core/services/daily_ayah_widget_service.dart';
import 'core/services/daily_notification_service.dart';
import 'core/services/llm_service.dart';
import 'core/services/local_quran_asset_service.dart';
import 'core/services/model_manager.dart';
import 'core/services/quran_user_session_service.dart';
import 'core/services/vector_store_service.dart' show VectorStoreService, kEmotionalVerses;

AppLifecycleListener? _appLifecycleListener;

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
    systemNavigationBarColor: Color(0xFF060B11),
  ));

  _appLifecycleListener = AppLifecycleListener(
    onResume: () {
      unawaited(DailyNotificationService.instance.initialize());
    },
  );
  assert(_appLifecycleListener != null);

  runApp(const ProviderScope(child: NoorAiApp()));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_warmUpCoreServices());
  });
}

Future<void> _warmUpCoreServices() async {
  unawaited(_runStartupTask('vector store init', () async {
    await VectorStoreService.instance.initialize();
    if (await VectorStoreService.instance.hasReadyNativeCorpus()) {
      return 'bundled-native-corpus-ready';
    }
    if (VectorStoreService.instance.usesNativeZvec) {
      await LocalQuranAssetService.instance.initialize();
      final built = await VectorStoreService.instance.ensureAndroidNativeCorpusBuilt(
        loadDocuments: LocalQuranAssetService.instance.loadVectorDocuments,
        emotionalVerses: kEmotionalVerses,
      );
      if (built) {
        return 'android-native-corpus-built';
      }
    }
    return VectorStoreService.instance.usesNativeZvec
        ? 'native-runtime-ready-without-bundled-db'
        : 'in-memory-fallback-ready';
  }));

  unawaited(_runStartupTask(
    'local Quran asset init',
    LocalQuranAssetService.instance.initialize,
  ));

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
  unawaited(_runStartupTask(
    'LLM engine init',
    () => LlmService.instance.initialize(),
  ));
  unawaited(_runStartupTask(
    'daily ayah widget sync',
    DailyAyahWidgetService.instance.syncTodayAyahWidget,
  ));
  unawaited(_runStartupTask(
    'daily notification init',
    DailyNotificationService.instance.initialize,
  ));
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
