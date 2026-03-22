#ifndef EDGEMIND_CORE_H
#define EDGEMIND_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_MSC_VER)
#define EDGEMIND_EXPORT __declspec(dllexport)
#elif defined(__GNUC__)
#define EDGEMIND_EXPORT __attribute__((visibility("default")))
#else
#define EDGEMIND_EXPORT
#endif

// =============================================================================
// FFI Data Structures
// =============================================================================

typedef struct {
  int32_t success;
  int32_t error_code;
  const char *error_message;
} FfiResult;

typedef struct {
  int32_t success;
  int32_t error_code;
  const char *value;
} FfiStringResult;

// StreamCallback for chat generation
typedef void (*StreamCallback)(const char *token, int32_t is_final,
                               void *user_data);

// =============================================================================
// Lifecycle
// =============================================================================

EDGEMIND_EXPORT FfiResult edgemind_initialize(const char *config_json);
EDGEMIND_EXPORT FfiResult edgemind_shutdown();
EDGEMIND_EXPORT int32_t edgemind_is_initialized();

// =============================================================================
// Chat
// =============================================================================

EDGEMIND_EXPORT FfiStringResult edgemind_chat(const char *message,
                                              const char *conversation_id);

EDGEMIND_EXPORT FfiResult edgemind_chat_stream(
    const char *message, const char *conversation_id, int32_t thinking_enabled,
    int32_t use_documents, const char *focused_doc_id, StreamCallback callback,
    void *user_data);

EDGEMIND_EXPORT FfiResult edgemind_cancel_generation();

// =============================================================================
// System & Utilities
// =============================================================================

EDGEMIND_EXPORT const char *edgemind_version();
EDGEMIND_EXPORT int32_t edgemind_mnn_available();
EDGEMIND_EXPORT const char *edgemind_mnn_version();
EDGEMIND_EXPORT FfiStringResult edgemind_embed_text(const char *embedding_path,
                                                    const char *text,
                                                    int32_t is_query);
EDGEMIND_EXPORT void edgemind_free_string(const char *s);
EDGEMIND_EXPORT intptr_t edgemind_memory_usage();

// Register / unregister Dart NativeCallable trampolines so native detached
// threads can safely skip callbacks when Dart is unavailable (hot restart).
EDGEMIND_EXPORT void edgemind_register_dart_callbacks(StreamCallback llm_cb,
                                                      StreamCallback asr_cb);
EDGEMIND_EXPORT void edgemind_unregister_dart_callbacks();

// =============================================================================
// RAG & Knowledge Base
// =============================================================================

EDGEMIND_EXPORT FfiStringResult edgemind_add_source(const char *content,
                                                    const char *metadata);
EDGEMIND_EXPORT FfiStringResult edgemind_list_sources();
EDGEMIND_EXPORT FfiResult edgemind_delete_source(const char *doc_id);
EDGEMIND_EXPORT FfiStringResult edgemind_search_knowledge(const char *query,
                                                          int32_t limit);
EDGEMIND_EXPORT FfiStringResult edgemind_search_in_document(const char *doc_id,
                                                            const char *query,
                                                            int32_t limit);
EDGEMIND_EXPORT FfiStringResult
edgemind_add_paged_document(const char *pages_json, const char *metadata_json);
EDGEMIND_EXPORT FfiResult edgemind_rebuild_sources_index();

// =============================================================================
// Audio Transcription
// =============================================================================

// Transcribe audio file to text. Returns JSON: {"text": "..."}
// audio_path: path to WAV file (16kHz, mono, 16-bit PCM)
EDGEMIND_EXPORT FfiStringResult edgemind_transcribe_audio(const char *audio_path);

// Stream chunk-level transcription updates. Callback receives cumulative text.
// is_final: 0=partial update, 1=complete, -1=error.
EDGEMIND_EXPORT FfiResult edgemind_transcribe_audio_stream(
  const char *audio_path, StreamCallback callback, void *user_data);

// Pre-load the ASR model bundle. Optional — transcribe_audio auto-loads.
// model_dir: directory containing the sherpa-mnn model bundle files.
EDGEMIND_EXPORT FfiResult edgemind_init_whisper(const char *model_dir);

// Enable or disable RNNoise preprocessing in the ASR pipeline.
EDGEMIND_EXPORT FfiResult edgemind_set_asr_rnnoise_enabled(int32_t enabled);

// =============================================================================
// Text-to-Speech (Supertonic TTS via MNN)
// =============================================================================

// Initialize Supertonic TTS engine.
// model_dir: directory containing mnn_models/, voice_styles/ subdirectories.
// voice: Supertonic voice style id such as M1, M2, F1, or F2.
EDGEMIND_EXPORT FfiResult edgemind_tts_init(const char *model_dir,
                                            const char *voice);

// Synthesize speech from text and write to a WAV file.
// output_path: path for the output 44100Hz 16-bit mono WAV file.
EDGEMIND_EXPORT FfiResult edgemind_tts_synthesize(const char *text,
                                                  const char *output_path);

// Set software gain for synthesized TTS audio before WAV encoding.
// gain: clamped to a safe range, where 1.0 means default loudness.
EDGEMIND_EXPORT FfiResult edgemind_tts_set_gain(float gain);

// Check if TTS engine is available (compiled in and loaded).
EDGEMIND_EXPORT int32_t edgemind_tts_is_available();

// =============================================================================
// Conversations
// =============================================================================

EDGEMIND_EXPORT FfiStringResult edgemind_list_conversations();
EDGEMIND_EXPORT FfiStringResult edgemind_load_conversation(const char *id);
EDGEMIND_EXPORT FfiResult edgemind_delete_conversation(const char *id);

// =============================================================================
// Binary Protocol for Performance Optimization
// =============================================================================

// Asynchronous binary protocol APIs for reduced serialization overhead
EDGEMIND_EXPORT FfiResult edgemind_chat_binary_async(
    const uint8_t* request_data,
    size_t request_size,
    uint8_t** response_data,
    size_t* response_size
);

EDGEMIND_EXPORT FfiResult edgemind_embedding_binary_async(
    const uint8_t* request_data,
    size_t request_size,
    uint8_t** response_data,
    size_t* response_size
);

EDGEMIND_EXPORT void edgemind_free_binary_data(uint8_t* data);

#ifdef __cplusplus
}
#endif

#endif // EDGEMIND_CORE_H
