// ignore_for_file: avoid_print, non_constant_identifier_names

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:async';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════
// Native Library Loading
// ═══════════════════════════════════════════════════════════════════════

DynamicLibrary? _nativeLibCached;
bool _nativeAvailable = false;

DynamicLibrary get _nativeLib {
  _nativeLibCached ??= _loadLibrary();
  return _nativeLibCached!;
}

DynamicLibrary _loadLibrary() {
  try {
    final DynamicLibrary lib;
    if (Platform.isAndroid) {
      // Load MNN dependencies first (order matters for linker)
      for (final dep in [
        'libc++_shared.so',
        'libMNN.so',
        'libMNN_Express.so',
        'libmnncore.so',
        'libMNN_CL.so',
        'libMNN_Vulkan.so',
        'libMNNAudio.so',
        'libMNNOpenCV.so',
        'libllm.so',
      ]) {
        try {
          DynamicLibrary.open(dep);
        } catch (_) {
          debugPrint('NativeBridge: Optional dep $dep not found');
        }
      }
      lib = DynamicLibrary.open('libedgemind_core.so');
    } else if (Platform.isIOS) {
      lib = DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      lib = DynamicLibrary.process();
    } else {
      lib = DynamicLibrary.open('libedgemind_core.so');
    }
    _nativeAvailable = true;
    return lib;
  } catch (e) {
    debugPrint('NoorBridge: Native library not available: $e');
    _nativeAvailable = false;
    rethrow;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FFI Struct Definitions
// ═══════════════════════════════════════════════════════════════════════

final class FfiResult extends Struct {
  @Int32()
  external int success;

  @Int32()
  external int errorCode;

  external Pointer<Utf8> errorMessage;

  bool get isSuccess => success == 1;

  String? get error {
    if (errorMessage == nullptr) return null;
    return errorMessage.toDartString();
  }
}

final class FfiStringResult extends Struct {
  @Int32()
  external int success;

  @Int32()
  external int errorCode;

  external Pointer<Utf8> value;

  bool get isSuccess => success == 1;

  String? get stringValue {
    if (value == nullptr) return null;
    return value.toDartString();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FFI Type Definitions
// ═══════════════════════════════════════════════════════════════════════

// Callback for streaming tokens
typedef StreamCallback = Void Function(
    Pointer<Utf8> token, Int32 isFinal, Pointer<Void> userData);

// Lifecycle
typedef _InitializeNative = FfiResult Function(Pointer<Utf8> configJson);
typedef _InitializeDart = FfiResult Function(Pointer<Utf8> configJson);
typedef _ShutdownNative = FfiResult Function();
typedef _ShutdownDart = FfiResult Function();

// LLM
typedef _ChatStreamNative = FfiResult Function(
    Pointer<Utf8> message, Pointer<Utf8> conversationId, Int32 thinkingEnabled,
    Int32 useDocuments, Pointer<Utf8> focusedDocId,
    Pointer<NativeFunction<StreamCallback>> callback, Pointer<Void> userData);
typedef _ChatStreamDart = FfiResult Function(
    Pointer<Utf8> message, Pointer<Utf8> conversationId, int thinkingEnabled,
    int useDocuments, Pointer<Utf8> focusedDocId,
    Pointer<NativeFunction<StreamCallback>> callback, Pointer<Void> userData);
typedef _CancelGenerationNative = FfiResult Function();
typedef _CancelGenerationDart = FfiResult Function();

// ASR
typedef _TranscribeAudioNative = FfiStringResult Function(Pointer<Utf8> audioPath);
typedef _TranscribeAudioDart = FfiStringResult Function(Pointer<Utf8> audioPath);
typedef _TranscribeAudioStreamNative = FfiResult Function(
  Pointer<Utf8> audioPath,
  Pointer<NativeFunction<StreamCallback>> callback,
  Pointer<Void> userData);
typedef _TranscribeAudioStreamDart = FfiResult Function(
  Pointer<Utf8> audioPath,
  Pointer<NativeFunction<StreamCallback>> callback,
  Pointer<Void> userData);
typedef _InitWhisperNative = FfiResult Function(Pointer<Utf8> modelDir);
typedef _InitWhisperDart = FfiResult Function(Pointer<Utf8> modelDir);

// TTS
typedef _TtsInitNative = FfiResult Function(Pointer<Utf8> modelDir, Pointer<Utf8> voiceId);
typedef _TtsInitDart = FfiResult Function(Pointer<Utf8> modelDir, Pointer<Utf8> voiceId);
typedef _TtsSynthesizeNative = FfiResult Function(Pointer<Utf8> text, Pointer<Utf8> outputPath);
typedef _TtsSynthesizeDart = FfiResult Function(Pointer<Utf8> text, Pointer<Utf8> outputPath);
typedef _TtsIsAvailableNative = Int32 Function();
typedef _TtsIsAvailableDart = int Function();
typedef _TtsSetGainNative = FfiResult Function(Float gain);
typedef _TtsSetGainDart = FfiResult Function(double gain);

// RAG / Vector search
typedef _SearchKnowledgeNative = FfiStringResult Function(Pointer<Utf8> query, Int32 limit);
typedef _SearchKnowledgeDart = FfiStringResult Function(Pointer<Utf8> query, int limit);
typedef _SearchInDocumentNative = FfiStringResult Function(Pointer<Utf8> docId, Pointer<Utf8> query, Int32 limit);
typedef _SearchInDocumentDart = FfiStringResult Function(Pointer<Utf8> docId, Pointer<Utf8> query, int limit);
typedef _AddPagedDocumentNative = FfiStringResult Function(Pointer<Utf8> pagesJson, Pointer<Utf8> metadataJson);
typedef _AddPagedDocumentDart = FfiStringResult Function(Pointer<Utf8> pagesJson, Pointer<Utf8> metadataJson);
typedef _EmbedTextNative = FfiStringResult Function(Pointer<Utf8> embeddingPath, Pointer<Utf8> text, Int32 isQuery);
typedef _EmbedTextDart = FfiStringResult Function(Pointer<Utf8> embeddingPath, Pointer<Utf8> text, int isQuery);

// Memory management
typedef _FreeStringNative = Void Function(Pointer<Utf8> s);
typedef _FreeStringDart = void Function(Pointer<Utf8> s);

// ═══════════════════════════════════════════════════════════════════════
// Function pointers (lazy-loaded)
// ═══════════════════════════════════════════════════════════════════════

_InitializeDart? _initializeFunc;
_ShutdownDart? _shutdownFunc;
_ChatStreamDart? _chatStreamFunc;
_CancelGenerationDart? _cancelGenerationFunc;
_TranscribeAudioDart? _transcribeAudioFunc;
_TranscribeAudioStreamDart? _transcribeAudioStreamFunc;
_InitWhisperDart? _initWhisperFunc;
_TtsInitDart? _ttsInitFunc;
_TtsSynthesizeDart? _ttsSynthesizeFunc;
_TtsIsAvailableDart? _ttsIsAvailableFunc;
_TtsSetGainDart? _ttsSetGainFunc;
_SearchKnowledgeDart? _searchKnowledgeFunc;
_SearchInDocumentDart? _searchInDocumentFunc;
_AddPagedDocumentDart? _addPagedDocumentFunc;
_EmbedTextDart? _embedTextFunc;
_FreeStringDart? _freeStringFunc;

bool _functionsLoaded = false;

void _releaseNativeString(Pointer<Utf8> value) {
  if (value != nullptr) {
    _freeStringFunc?.call(value);
  }
}

void _loadFunctions() {
  if (_functionsLoaded) return;

  try {
    final lib = _nativeLib;

    _initializeFunc = lib
        .lookup<NativeFunction<_InitializeNative>>('edgemind_initialize')
        .asFunction<_InitializeDart>();

    _shutdownFunc = lib
        .lookup<NativeFunction<_ShutdownNative>>('edgemind_shutdown')
        .asFunction<_ShutdownDart>();

    _chatStreamFunc = lib
        .lookup<NativeFunction<_ChatStreamNative>>('edgemind_chat_stream')
        .asFunction<_ChatStreamDart>();

    _cancelGenerationFunc = lib
        .lookup<NativeFunction<_CancelGenerationNative>>('edgemind_cancel_generation')
        .asFunction<_CancelGenerationDart>();

    _transcribeAudioFunc = lib
        .lookup<NativeFunction<_TranscribeAudioNative>>('edgemind_transcribe_audio')
        .asFunction<_TranscribeAudioDart>();

    _transcribeAudioStreamFunc = lib
      .lookup<NativeFunction<_TranscribeAudioStreamNative>>(
        'edgemind_transcribe_audio_stream')
      .asFunction<_TranscribeAudioStreamDart>();

    _initWhisperFunc = lib
        .lookup<NativeFunction<_InitWhisperNative>>('edgemind_init_whisper')
        .asFunction<_InitWhisperDart>();

    _ttsInitFunc = lib
        .lookup<NativeFunction<_TtsInitNative>>('edgemind_tts_init')
        .asFunction<_TtsInitDart>();

    _ttsSynthesizeFunc = lib
        .lookup<NativeFunction<_TtsSynthesizeNative>>('edgemind_tts_synthesize')
        .asFunction<_TtsSynthesizeDart>();

    _ttsIsAvailableFunc = lib
        .lookup<NativeFunction<_TtsIsAvailableNative>>('edgemind_tts_is_available')
        .asFunction<_TtsIsAvailableDart>();

    _ttsSetGainFunc = lib
        .lookup<NativeFunction<_TtsSetGainNative>>('edgemind_tts_set_gain')
        .asFunction<_TtsSetGainDart>();

    _searchKnowledgeFunc = lib
        .lookup<NativeFunction<_SearchKnowledgeNative>>('edgemind_search_knowledge')
        .asFunction<_SearchKnowledgeDart>();

    _searchInDocumentFunc = lib
      .lookup<NativeFunction<_SearchInDocumentNative>>('edgemind_search_in_document')
      .asFunction<_SearchInDocumentDart>();

    _addPagedDocumentFunc = lib
        .lookup<NativeFunction<_AddPagedDocumentNative>>('edgemind_add_paged_document')
        .asFunction<_AddPagedDocumentDart>();

    _embedTextFunc = lib
      .lookup<NativeFunction<_EmbedTextNative>>('edgemind_embed_text')
      .asFunction<_EmbedTextDart>();

    _freeStringFunc = lib
        .lookup<NativeFunction<_FreeStringNative>>('edgemind_free_string')
        .asFunction<_FreeStringDart>();

    _functionsLoaded = true;
  } catch (e) {
    debugPrint('NoorBridge: Failed to load native functions: $e');
    _nativeAvailable = false;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Public API – NativeBridge
// ═══════════════════════════════════════════════════════════════════════

class NativeBridge {
  NativeBridge._();
  static final NativeBridge instance = NativeBridge._();

  bool get isAvailable {
    try {
      _loadFunctions();
      return _nativeAvailable && _functionsLoaded;
    } catch (_) {
      return false;
    }
  }

  // ── Lifecycle ──

  FfiResult initialize(String configJson) {
    _loadFunctions();
    final ptr = configJson.toNativeUtf8();
    try {
      return _initializeFunc!(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  FfiResult shutdown() {
    _loadFunctions();
    return _shutdownFunc!();
  }

  // ── ASR ──

  FfiResult initWhisper(String modelDir) {
    _loadFunctions();
    final ptr = modelDir.toNativeUtf8();
    try {
      return _initWhisperFunc!(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  String? transcribeAudio(String audioPath) {
    _loadFunctions();
    final ptr = audioPath.toNativeUtf8();
    try {
      final result = _transcribeAudioFunc!(ptr);
      final valuePtr = result.value;
      if (!result.isSuccess) {
        try {
          debugPrint(
            'NoorBridge: Transcription failed '
            '(code=${result.errorCode}): ${result.stringValue ?? "Unknown error"}',
          );
          return null;
        } finally {
          _releaseNativeString(valuePtr);
        }
      }

      try {
        final payload = result.stringValue;
        if (payload == null || payload.isEmpty) {
          return null;
        }

        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          final text = decoded['text'];
          if (text is String) {
            return text;
          }
        }

        return payload;
      } catch (_) {
        // Fall back to the raw native string if the payload isn't JSON.
        return result.stringValue;
      } finally {
        _releaseNativeString(valuePtr);
      }
    } finally {
      calloc.free(ptr);
    }
  }

  Stream<String> transcribeAudioStream(String audioPath) {
    _loadFunctions();
    final controller = StreamController<String>();
    final pathPtr = audioPath.toNativeUtf8();

    late final NativeCallable<StreamCallback> nativeCallback;
    nativeCallback = NativeCallable<StreamCallback>.listener(
      (Pointer<Utf8> token, int isFinal, Pointer<Void> userData) {
        try {
          final text = token == nullptr ? '' : token.toDartString();
          _releaseNativeString(token);

          if (isFinal == -1) {
            controller.addError(Exception(
              text.isEmpty ? 'ASR transcription failed' : text,
            ));
            controller.close();
            nativeCallback.close();
            return;
          }

          if (text.isNotEmpty) {
            controller.add(text);
          }

          if (isFinal == 1) {
            controller.close();
            nativeCallback.close();
          }
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          controller.close();
          nativeCallback.close();
        }
      },
    );

    final result = _transcribeAudioStreamFunc!(
      pathPtr,
      nativeCallback.nativeFunction,
      nullptr,
    );

    calloc.free(pathPtr);

    if (!result.isSuccess) {
      controller.addError(Exception(result.error ?? 'ASR transcription failed'));
      controller.close();
      nativeCallback.close();
    }

    return controller.stream;
  }

  // ── LLM (Streaming) ──

  /// Stream tokens from the LLM. Returns a broadcast stream of token strings.
  Stream<String> chatStream(String message, {String? conversationId}) {
    _loadFunctions();
    final controller = StreamController<String>.broadcast();

    final msgPtr = message.toNativeUtf8();
    final convPtr = (conversationId ?? '').toNativeUtf8();
    final docPtr = ''.toNativeUtf8();

    // Create a native callback listener
    late final NativeCallable<StreamCallback> nativeCallback;
    nativeCallback = NativeCallable<StreamCallback>.listener(
      (Pointer<Utf8> token, int isFinal, Pointer<Void> userData) {
        if (token != nullptr) {
          final text = token.toDartString();
          _releaseNativeString(token);
          if (text.isNotEmpty) {
            controller.add(text);
          }
        }
        if (isFinal == 1) {
          controller.close();
          nativeCallback.close();
        }
      },
    );

    final result = _chatStreamFunc!(
      msgPtr, convPtr, 0, 0, docPtr,
      nativeCallback.nativeFunction, nullptr,
    );

    calloc.free(msgPtr);
    calloc.free(convPtr);
    calloc.free(docPtr);

    if (!result.isSuccess) {
      controller.addError(Exception(result.error ?? 'LLM generation failed'));
      controller.close();
      nativeCallback.close();
    }

    return controller.stream;
  }

  void cancelGeneration() {
    _loadFunctions();
    _cancelGenerationFunc!();
  }

  // ── TTS ──

  FfiResult ttsInit(String modelDir, String voiceId) {
    _loadFunctions();
    final modelPtr = modelDir.toNativeUtf8();
    final voicePtr = voiceId.toNativeUtf8();
    try {
      return _ttsInitFunc!(modelPtr, voicePtr);
    } finally {
      calloc.free(modelPtr);
      calloc.free(voicePtr);
    }
  }

  bool ttsSynthesize(String text, String outputPath) {
    _loadFunctions();
    final textPtr = text.toNativeUtf8();
    final pathPtr = outputPath.toNativeUtf8();
    try {
      final result = _ttsSynthesizeFunc!(textPtr, pathPtr);
      return result.isSuccess;
    } finally {
      calloc.free(textPtr);
      calloc.free(pathPtr);
    }
  }

  bool get ttsIsAvailable {
    _loadFunctions();
    return _ttsIsAvailableFunc!() == 1;
  }

  void ttsSetGain(double gain) {
    _loadFunctions();
    _ttsSetGainFunc!(gain);
  }

  // ── RAG / Vector Search (zvec) ──

  /// Search the native zvec knowledge base.
  /// Returns a JSON string: `[{"doc_id":..., "chunk_id":..., "score":..., "content":..., "metadata":{...}}, ...]`
  String? searchKnowledge(String query, {int limit = 5}) {
    _loadFunctions();
    final queryPtr = query.toNativeUtf8();
    try {
      final result = _searchKnowledgeFunc!(queryPtr, limit);
      final valuePtr = result.value;
      try {
        if (!result.isSuccess) {
          return null;
        }
        return result.stringValue;
      } finally {
        _releaseNativeString(valuePtr);
      }
    } finally {
      calloc.free(queryPtr);
    }
  }

  /// Search only within a single logical document hash in the native zvec knowledge base.
  String? searchInDocument(String documentId, String query, {int limit = 5}) {
    _loadFunctions();
    final documentPtr = documentId.toNativeUtf8();
    final queryPtr = query.toNativeUtf8();
    try {
      final result = _searchInDocumentFunc!(documentPtr, queryPtr, limit);
      final valuePtr = result.value;
      try {
        if (!result.isSuccess) {
          return null;
        }
        return result.stringValue;
      } finally {
        _releaseNativeString(valuePtr);
      }
    } finally {
      calloc.free(documentPtr);
      calloc.free(queryPtr);
    }
  }

  /// Add a paged document to the native zvec knowledge base.
  /// [pagesJson] is a JSON array of `[{"text": "..."}, ...]`.
  /// [metadataJson] is a JSON object with at least a `"hash"` field.
  /// Returns the hash of the inserted document, or null on failure.
  String? addPagedDocument(String pagesJson, String metadataJson) {
    _loadFunctions();
    final pagesPtr = pagesJson.toNativeUtf8();
    final metaPtr = metadataJson.toNativeUtf8();
    try {
      final result = _addPagedDocumentFunc!(pagesPtr, metaPtr);
      final valuePtr = result.value;
      try {
        if (!result.isSuccess) {
          return null;
        }
        return result.stringValue;
      } finally {
        _releaseNativeString(valuePtr);
      }
    } finally {
      calloc.free(pagesPtr);
      calloc.free(metaPtr);
    }
  }

  List<double>? embedText(
    String embeddingPath,
    String text, {
    bool isQuery = false,
  }) {
    _loadFunctions();
    final pathPtr = embeddingPath.toNativeUtf8();
    final textPtr = text.toNativeUtf8();
    try {
      final result = _embedTextFunc!(pathPtr, textPtr, isQuery ? 1 : 0);
      final valuePtr = result.value;
      try {
        if (!result.isSuccess) {
          return null;
        }
        final payload = result.stringValue;
        if (payload == null || payload.isEmpty) {
          return null;
        }
        final decoded = jsonDecode(payload);
        if (decoded is! List) {
          return null;
        }
        return decoded
            .map((item) => (item as num).toDouble())
            .toList(growable: false);
      } finally {
        _releaseNativeString(valuePtr);
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(textPtr);
    }
  }
}
