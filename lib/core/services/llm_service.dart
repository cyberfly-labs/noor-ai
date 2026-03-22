import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'native_bridge.dart';
import 'model_manager.dart';
import '../utils/perf_trace.dart';

/// On-device LLM service wrapping Qwen3.5-0.8B for Quran explanations
class LlmService {
  LlmService._();
  static final LlmService instance = LlmService._();

  bool _initialized = false;
  Future<bool>? _initializeFuture;
  bool get isInitialized => _initialized;

  /// Initialize the LLM runtime (called on first use)
  Future<bool> initialize() async {
    if (_initialized) return true;

    final pending = _initializeFuture;
    if (pending != null) {
      return pending;
    }

    final future = _initializeInternal();
    _initializeFuture = future;
    return future;
  }

  Future<bool> _initializeInternal() async {
    if (!NativeBridge.instance.isAvailable) {
      debugPrint('LlmService: Native bridge not available');
      _initializeFuture = null;
      return false;
    }

    try {
      await ModelManager.instance.initialize();
      await ModelManager.instance.ensureRuntimeReady(ModelType.llm);

      final hasLlmModel =
          await ModelManager.instance.isModelDownloaded(ModelType.llm);
      if (!hasLlmModel) {
        debugPrint('LlmService: LLM model not downloaded');
        _initializeFuture = null;
        return false;
      }

      final modelDir = ModelManager.instance.modelPath(ModelType.llm);
      if (modelDir.isEmpty) {
        debugPrint('LlmService: LLM model directory is empty');
        _initializeFuture = null;
        return false;
      }

      final configJson = jsonEncode({
        'data_dir': modelDir,
        'models': {
          'embedding_path': ModelManager.instance.modelPath(ModelType.embedding),
          'whisper_dir': ModelManager.instance.modelPath(ModelType.asr),
        },
        'storage': {
          'db_path': '${ModelManager.instance.modelsPath}/zvec_db',
        },
      });

      final result = NativeBridge.instance.initialize(configJson);
      _initialized = result.isSuccess;
      debugPrint('LlmService: Init ${_initialized ? "OK" : "FAILED"}');
      if (!_initialized) {
        _initializeFuture = null;
      }
      return _initialized;
    } catch (e) {
      debugPrint('LlmService: Init error: $e');
      _initializeFuture = null;
      return false;
    }
  }

  /// Generate a streaming response from the LLM
  Stream<String> generate(String prompt) async* {
    final traceTag = PerfTrace.nextTag('llm.generate');
    final totalSw = PerfTrace.start(traceTag, 'generate');
    final firstTokenSw = Stopwatch()..start();
    if (!NativeBridge.instance.isAvailable) {
      throw Exception('Native bridge not available');
    }

    final ready = await initialize();
    if (!ready) {
      throw Exception('LLM runtime initialization failed');
    }

    // Wrap the raw stream with repetition detection
    final buffer = StringBuffer();
    var tokenCount = 0;
    var emittedAnyToken = false;
    await for (final token in NativeBridge.instance.chatStream(prompt)) {
      if (!emittedAnyToken) {
        emittedAnyToken = true;
        PerfTrace.mark(traceTag, 'first_token', firstTokenSw);
      }
      buffer.write(token);
      tokenCount += 1;
      final shouldCheckRepetition = tokenCount % 12 == 0;
      if (shouldCheckRepetition && _hasRepetitionLoop(buffer.toString())) {
        debugPrint('LlmService: Repetition loop detected, stopping generation');
        cancelGeneration();
        break;
      }
      yield token;
    }

    if (!emittedAnyToken) {
      PerfTrace.mark(traceTag, 'no_tokens', firstTokenSw);
    }
    PerfTrace.end(traceTag, 'generate', totalSw);
  }

  /// Detects if the generated text has fallen into a repetition loop.
  /// Checks if any sentence/paragraph of 40+ chars repeats 3+ times.
  static bool _hasRepetitionLoop(String text) {
    if (text.length < 150) return false;
    // Check for repeated blocks: slide a window of size W and look for a
    // substring that appears 3+ times in the tail portion.
    // Use sentence-level detection: split on periods/newlines and check
    // if recent sentences repeat earlier ones.
    final sentences = text
        .split(RegExp(r'[.\n]'))
        .map((s) => s.trim())
        .where((s) => s.length >= 30)
        .toList();
    if (sentences.length < 4) return false;

    // Count occurrences of the last 2 sentences in all sentences
    final tail = sentences.sublist(sentences.length - 2);
    for (final sentence in tail) {
      int count = 0;
      for (final s in sentences) {
        if (s == sentence) count++;
      }
      if (count >= 3) return true;
    }
    return false;
  }

  /// Generate a complete response (non-streaming)
  Future<String> generateComplete(String prompt) async {
    final buffer = StringBuffer();
    await for (final token in generate(prompt)) {
      buffer.write(token);
    }
    return buffer.toString();
  }

  /// Cancel ongoing generation
  void cancelGeneration() {
    NativeBridge.instance.cancelGeneration();
  }

  Future<void> shutdown() async {
    if (!_initialized) return;
    NativeBridge.instance.shutdown();
    _initialized = false;
  }
}
