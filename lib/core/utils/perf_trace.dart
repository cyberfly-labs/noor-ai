import 'package:flutter/foundation.dart';

/// Minimal debug-only tracing utility for latency instrumentation.
class PerfTrace {
  PerfTrace._();

  static bool get enabled => kDebugMode;

  static int _counter = 0;

  static String nextTag(String scope) {
    _counter += 1;
    return '$scope#$_counter';
  }

  static Stopwatch start(String tag, String stage) {
    final sw = Stopwatch()..start();
    if (enabled) {
      debugPrint('PerfTrace[$tag] START $stage');
    }
    return sw;
  }

  static void mark(String tag, String stage, Stopwatch sw) {
    if (!enabled) {
      return;
    }
    debugPrint('PerfTrace[$tag] $stage ${sw.elapsedMilliseconds}ms');
  }

  static void end(String tag, String stage, Stopwatch sw) {
    if (!enabled) {
      return;
    }
    debugPrint('PerfTrace[$tag] END $stage ${sw.elapsedMilliseconds}ms');
  }
}
