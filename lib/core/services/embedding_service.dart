import 'package:flutter/foundation.dart';

import 'model_manager.dart';
import 'native_bridge.dart';

/// Embedding service wrapping bge-small-en-v1.5-mnn for text embeddings
class EmbeddingService {
  EmbeddingService._();
  static final EmbeddingService instance = EmbeddingService._();

  bool _initialized = false;
  bool _nativeEmbeddingAvailable = false;
  String _embeddingModelPath = '';
  final Map<String, List<double>> _queryCache = <String, List<double>>{};
  final Map<String, List<double>> _documentCache = <String, List<double>>{};
  static const int _maxCacheEntries = 128;
  bool get isInitialized => _initialized;

  /// Embedding dimension for bge-small-en-v1.5
  static const int dimension = 384;

  Future<bool> initialize() async {
    if (_initialized) return true;

    await ModelManager.instance.initialize();
    await ModelManager.instance.ensureRuntimeReady(ModelType.embedding);

    final hasEmbeddingModel =
        await ModelManager.instance.isModelDownloaded(ModelType.embedding);
    if (!hasEmbeddingModel || !NativeBridge.instance.isAvailable) {
      _initialized = true;
      debugPrint('EmbeddingService: Ready (placeholder mode)');
      return true;
    }

    try {
      _embeddingModelPath = ModelManager.instance.modelPath(ModelType.embedding);
      _nativeEmbeddingAvailable = _embeddingModelPath.isNotEmpty;
      _initialized = true;
      debugPrint(
        'EmbeddingService: Ready '
        '(${_nativeEmbeddingAvailable ? "native" : "placeholder"})',
      );
      return true;
    } catch (e) {
      debugPrint('EmbeddingService: Init error: $e');
      return false;
    }
  }

  /// Generate embedding vector for text (placeholder until native integration)
  /// In production, this calls the native embedding model.
  /// For now, returns a simple hash-based pseudo-embedding for development.
  List<double> embed(String text, {bool isQuery = false}) {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return List<double>.filled(dimension, 0.0);
    }

    if (!_initialized) {
      _initialized = true;
      debugPrint('EmbeddingService: Ready (lazy placeholder mode)');
    }

    final cacheKey = normalizedText.toLowerCase();
    final cache = isQuery ? _queryCache : _documentCache;
    final cached = cache[cacheKey];
    if (cached != null) {
      return cached;
    }

    if (_nativeEmbeddingAvailable) {
      final vector = NativeBridge.instance.embedText(
        _embeddingModelPath,
        normalizedText,
        isQuery: isQuery,
      );
      if (vector != null && vector.length == dimension) {
        _putCacheEntry(cache, cacheKey, vector);
        return vector;
      }
      debugPrint('EmbeddingService: Native embedding failed, using placeholder');
    }
    
    // Development placeholder: deterministic pseudo-embedding based on text hash
    final hash = normalizedText.hashCode;
    final fallback = List.generate(dimension, (i) {
      final seed = (hash + i * 31) & 0x7FFFFFFF;
      return (seed / 0x7FFFFFFF) * 2.0 - 1.0;
    });
    _putCacheEntry(cache, cacheKey, fallback);
    return fallback;
  }

  void _putCacheEntry(
    Map<String, List<double>> cache,
    String key,
    List<double> vector,
  ) {
    if (cache.length >= _maxCacheEntries) {
      final firstKey = cache.keys.first;
      cache.remove(firstKey);
    }
    cache[key] = List<double>.unmodifiable(vector);
  }
}
