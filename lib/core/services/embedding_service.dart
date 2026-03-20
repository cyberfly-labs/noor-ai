import 'package:flutter/foundation.dart';

import 'native_bridge.dart';

/// Embedding service wrapping bge-small-en-v1.5-mnn for text embeddings
class EmbeddingService {
  EmbeddingService._();
  static final EmbeddingService instance = EmbeddingService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Embedding dimension for bge-small-en-v1.5
  static const int dimension = 384;

  Future<bool> initialize() async {
    if (_initialized) return true;
    if (!NativeBridge.instance.isAvailable) {
      _initialized = true;
      debugPrint('EmbeddingService: Ready (placeholder mode)');
      return true;
    }

    try {
      // Model initialization handled by native core during main initialize
      _initialized = true;
      debugPrint('EmbeddingService: Ready');
      return true;
    } catch (e) {
      debugPrint('EmbeddingService: Init error: $e');
      return false;
    }
  }

  /// Generate embedding vector for text (placeholder until native integration)
  /// In production, this calls the native embedding model.
  /// For now, returns a simple hash-based pseudo-embedding for development.
  List<double> embed(String text) {
    if (!_initialized) {
      _initialized = true;
      debugPrint('EmbeddingService: Ready (lazy placeholder mode)');
    }

    // TODO: Replace with native FFI call when fully integrated
    // return NativeBridge.instance.embed(text);
    
    // Development placeholder: deterministic pseudo-embedding based on text hash
    final hash = text.hashCode;
    return List.generate(dimension, (i) {
      final seed = (hash + i * 31) & 0x7FFFFFFF;
      return (seed / 0x7FFFFFFF) * 2.0 - 1.0;
    });
  }
}
