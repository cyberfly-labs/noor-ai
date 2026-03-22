/**
 * MNN C Wrapper for EdgeMind
 *
 * Provides a C API wrapper around MNN for safe FFI access from Rust.
 * Based on patterns from cyberfly-labs/kidance implementation.
 *
 * This header defines the C ABI interface for MNN operations:
 * - Engine creation/destruction
 * - Model loading (file and buffer)
 * - Inference execution
 * - Session pooling for concurrent access
 * - Shape and metadata queries
 */

#ifndef MNN_WRAPPER_H
#define MNN_WRAPPER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_MSC_VER)
#define MNNR_EXPORT __declspec(dllexport)
#elif defined(__GNUC__)
#define MNNR_EXPORT __attribute__((visibility("default")))
#else
#define MNNR_EXPORT
#endif

// =============================================================================
// Error Codes
// =============================================================================

typedef enum {
  MNNR_SUCCESS = 0,
  MNNR_ERROR_INVALID_PARAM = 1,
  MNNR_ERROR_OUT_OF_MEMORY = 2,
  MNNR_ERROR_RUNTIME = 3,
  MNNR_ERROR_UNSUPPORTED = 4,
  MNNR_ERROR_MODEL_LOAD_FAILED = 5,
  MNNR_ERROR_NULL_POINTER = 6,
  MNNR_ERROR_SHAPE_MISMATCH = 7,
} MNNR_ErrorCode;

// =============================================================================
// Backend Types
// =============================================================================

typedef enum {
  MNNR_BACKEND_CPU = 0,
  MNNR_BACKEND_METAL = 1,
  MNNR_BACKEND_OPENCL = 2,
  MNNR_BACKEND_OPENGL = 3,
  MNNR_BACKEND_VULKAN = 4,
  MNNR_BACKEND_NNAPI = 5,
  MNNR_BACKEND_COREML = 6,
} MNNR_Backend;

// =============================================================================
// Precision Modes
// =============================================================================

typedef enum {
  MNNR_PRECISION_NORMAL = 0,   // FP32
  MNNR_PRECISION_HIGH = 1,     // FP32 with higher accuracy
  MNNR_PRECISION_LOW = 2,      // FP16 or INT8
  MNNR_PRECISION_LOW_BF16 = 3, // BF16
} MNNR_Precision;

// =============================================================================
// Data Format
// =============================================================================

typedef enum {
  MNNR_FORMAT_NCHW = 0,   // Batch, Channel, Height, Width
  MNNR_FORMAT_NHWC = 1,   // Batch, Height, Width, Channel
  MNNR_FORMAT_NC4HW4 = 2, // MNN optimized format
} MNNR_DataFormat;

// =============================================================================
// Configuration
// =============================================================================

typedef struct {
  int32_t thread_count;
  int32_t backend;     // MNNR_Backend
  int32_t precision;   // MNNR_Precision
  int32_t data_format; // MNNR_DataFormat
} MNNR_Config;

// =============================================================================
// Opaque Handle Types
// =============================================================================

typedef void *MNNR_Engine;
typedef void *MNNR_SessionPool;

// =============================================================================
// Version & Info
// =============================================================================

/**
 * Get MNN library version string
 * @return Null-terminated version string (do not free)
 */
const char *mnnr_get_version(void);

/**
 * Check if MNN is available/compiled
 * @return 1 if available, 0 otherwise
 */
int mnnr_is_available(void);

// =============================================================================
// Engine Operations
// =============================================================================

/**
 * Create inference engine from model file
 *
 * @param model_path Path to .mnn model file
 * @param config Configuration options
 * @param error_code Output error code (can be NULL)
 * @return Engine handle or NULL on error
 */
MNNR_Engine mnnr_create_engine(const char *model_path,
                               const MNNR_Config *config, int32_t *error_code);

/**
 * Create inference engine from memory buffer
 *
 * @param buffer Model data buffer
 * @param buffer_size Size of buffer in bytes
 * @param config Configuration options
 * @param error_code Output error code (can be NULL)
 * @return Engine handle or NULL on error
 */
MNNR_Engine mnnr_create_engine_from_buffer(const void *buffer,
                                           size_t buffer_size,
                                           const MNNR_Config *config,
                                           int32_t *error_code);

/**
 * Destroy inference engine and free resources
 *
 * @param engine Engine handle (safe to pass NULL)
 */
MNNR_EXPORT void mnnr_destroy_engine(MNNR_Engine engine);

/**
 * Run inference on the engine
 *
 * @param engine Engine handle
 * @param input Input tensor data (float32)
 * @param input_size Number of input elements
 * @param output Output tensor buffer (float32)
 * @param output_size Number of output elements
 * @return MNNR_SUCCESS or error code
 */
MNNR_EXPORT uint32_t mnnr_run_inference(MNNR_Engine engine, const float *input,
                                        size_t input_size, float *output,
                                        size_t output_size);

/**
 * Get input tensor data buffer
 *
 * @param engine Engine handle
 * @param name Tensor name (NULL for default)
 * @return Pointer to tensor data or NULL
 */
MNNR_EXPORT void *mnnr_get_session_input(MNNR_Engine engine, const char *name);

/**
 * Get input tensor info (shape/dims)
 *
 * @param engine Engine handle
 * @param name Tensor name
 * @param shape Output shape (at least 8 ints)
 * @param ndim Output ndim
 * @return MNNR_SUCCESS or error
 */
MNNR_EXPORT uint32_t mnnr_get_session_input_info(MNNR_Engine engine,
                                                 const char *name,
                                                 int32_t *shape, int32_t *ndim);

/**
 * Resize specific session input
 *
 * @param engine Engine handle
 * @param name Tensor name
 * @param shape New shape array
 * @param ndim New dimensions
 * @return MNNR_SUCCESS or error
 */
MNNR_EXPORT uint32_t mnnr_resize_session_input(MNNR_Engine engine,
                                               const char *name,
                                               const int32_t *shape,
                                               int32_t ndim);

/**
 * Get output tensor data buffer
 *
 * @param engine Engine handle
 * @param name Tensor name (NULL for default)
 * @return Pointer to tensor data or NULL
 */
MNNR_EXPORT void *mnnr_get_session_output(MNNR_Engine engine, const char *name);

/**
 * Get output tensor info (shape/dims)
 *
 * @param engine Engine handle
 * @param name Tensor name
 * @param shape Output shape (at least 8 ints)
 * @param ndim Output ndim
 * @return MNNR_SUCCESS or error
 */
MNNR_EXPORT uint32_t mnnr_get_session_output_info(MNNR_Engine engine,
                                                  const char *name,
                                                  int32_t *shape,
                                                  int32_t *ndim);

// =============================================================================
// Shape Operations
// =============================================================================

/**
 * Get input tensor shape
 *
 * @param engine Engine handle
 * @param index Input tensor index (usually 0)
 * @param shape Output shape array (must hold at least 8 ints)
 * @param ndim Output number of dimensions
 * @return MNNR_SUCCESS or error code
 */
MNNR_EXPORT uint32_t mnnr_get_input_shape(MNNR_Engine engine, int32_t index,
                                          int32_t *shape, int32_t *ndim);

/**
 * Get output tensor shape
 *
 * @param engine Engine handle
 * @param index Output tensor index (usually 0)
 * @param shape Output shape array (must hold at least 8 ints)
 * @param ndim Output number of dimensions
 * @return MNNR_SUCCESS or error code
 */
MNNR_EXPORT uint32_t mnnr_get_output_shape(MNNR_Engine engine, int32_t index,
                                           int32_t *shape, int32_t *ndim);

/**
 * Resize input tensor for dynamic shapes
 *
 * @param engine Engine handle
 * @param index Input tensor index
 * @param shape New shape array
 * @param ndim Number of dimensions
 * @return MNNR_SUCCESS or error code
 */
MNNR_EXPORT uint32_t mnnr_resize_input(MNNR_Engine engine, int32_t index,
                                       const int32_t *shape, int32_t ndim);

// =============================================================================
// Session Pool Operations
// =============================================================================

/**
 * Create session pool for concurrent inference
 *
 * @param model_path Path to .mnn model file
 * @param config Configuration options
 * @param pool_size Number of sessions in pool
 * @return Pool handle or NULL on error
 */
MNNR_EXPORT MNNR_SessionPool mnnr_create_session_pool(const char *model_path,
                                                      const MNNR_Config *config,
                                                      int32_t pool_size);

/**
 * Destroy session pool
 *
 * @param pool Pool handle
 */
MNNR_EXPORT void mnnr_destroy_session_pool(MNNR_SessionPool pool);

/**
 * Run inference using pooled session
 * Thread-safe: will acquire available session automatically
 *
 * @param pool Pool handle
 * @param input Input tensor data
 * @param input_size Number of input elements
 * @param output Output tensor buffer
 * @param output_size Number of output elements
 * @return MNNR_SUCCESS or error code
 */
MNNR_EXPORT uint32_t mnnr_pool_run_inference(MNNR_SessionPool pool,
                                             const float *input,
                                             size_t input_size, float *output,
                                             size_t output_size);

/**
 * Get number of available sessions in pool
 *
 * @param pool Pool handle
 * @return Number of available sessions
 */
MNNR_EXPORT int32_t mnnr_pool_available_sessions(MNNR_SessionPool pool);

// =============================================================================
// Interpreter Operations (Standard MNN API for Embeddings)
// =============================================================================

/// Opaque Interpreter handle (wraps MNN::Interpreter)
typedef void *MNNR_Interpreter;

/// Opaque Session handle (wraps MNN::Session)
typedef void *MNNR_Session;

/**
 * Create interpreter from model file
 *
 * @param model_path Path to .mnn model file
 * @return Interpreter handle or NULL on error
 */
MNNR_EXPORT MNNR_Interpreter
mnnr_interpreter_create_from_file(const char *model_path);

/**
 * Create interpreter from buffer
 *
 * @param buffer Model buffer
 * @param size Buffer size
 * @return Interpreter handle or NULL on error
 */
MNNR_EXPORT MNNR_Interpreter
mnnr_interpreter_create_from_buffer(const void *buffer, size_t size);

/**
 * Destroy interpreter
 *
 * @param interpreter Interpreter handle
 */
MNNR_EXPORT void mnnr_interpreter_destroy(MNNR_Interpreter interpreter);

/**
 * Create session
 *
 * @param interpreter Interpreter handle
 * @param config Config options
 * @return Session handle or NULL on error
 */
MNNR_EXPORT MNNR_Session mnnr_interpreter_create_session(
    MNNR_Interpreter interpreter, const MNNR_Config *config);

/**
 * Run session
 *
 * @param interpreter Interpreter handle
 * @param session Session handle
 * @return MNNR_SUCCESS or error code
 */
MNNR_EXPORT uint32_t mnnr_interpreter_run(MNNR_Interpreter interpreter,
                                          MNNR_Session session);

/**
 * Resize input tensor
 *
 * @param interpreter Interpreter handle
 * @param session Session handle
 * @param name Input tensor name (or NULL for default)
 * @param shape New shape array
 * @param ndim Number of dimensions
 */
MNNR_EXPORT void mnnr_interpreter_resize_input(MNNR_Interpreter interpreter,
                                               MNNR_Session session,
                                               const char *name,
                                               const int32_t *shape,
                                               int32_t ndim);

/**
 * Resize session to apply shape changes
 *
 * @param interpreter Interpreter handle
 * @param session Session handle
 */
MNNR_EXPORT void mnnr_interpreter_resize_session(MNNR_Interpreter interpreter,
                                                 MNNR_Session session);

/**
 * Get input tensor data and info
 *
 * @param interpreter Interpreter handle
 * @param session Session handle
 * @param name Tensor name (can be NULL for default)
 * @param shape Output shape array (must hold at least 8 ints)
 * @param ndim Output number of dimensions
 * @return Pointer to tensor data (float*) or NULL on error
 */
MNNR_EXPORT void *
mnnr_interpreter_get_input_tensor(MNNR_Interpreter interpreter,
                                  MNNR_Session session, const char *name,
                                  int32_t *shape, int32_t *ndim);

/**
 * Get output tensor data and info
 *
 * @param interpreter Interpreter handle
 * @param session Session handle
 * @param name Tensor name (can be NULL for default)
 * @param shape Output shape array (must hold at least 8 ints)
 * @param ndim Output number of dimensions
 * @return Pointer to tensor data (float*) or NULL on error
 */
MNNR_EXPORT void *
mnnr_interpreter_get_output_tensor(MNNR_Interpreter interpreter,
                                   MNNR_Session session, const char *name,
                                   int32_t *shape, int32_t *ndim);

/**
 * Set global executor configuration (threads, backend)
 * Critical for LLM backend which uses global executor
 *
 * @param num_threads Number of threads to use
 * @param backend Backend type (MNNR_Backend)
 */
MNNR_EXPORT void mnnr_set_global_executor_config(int32_t num_threads,
                                                 int32_t backend);

// =============================================================================
// Memory Management
// =============================================================================

/**
 * Get estimated memory usage of engine
 *
 * @param engine Engine handle
 * @return Memory usage in bytes
 */
MNNR_EXPORT size_t mnnr_get_memory_usage(MNNR_Engine engine);

/**
 * Release any cached memory
 *
 * @param engine Engine handle
 */
MNNR_EXPORT void mnnr_release_cache(MNNR_Engine engine);

// =============================================================================
// LLM-Specific Operations (using MNN Transformer API)
// =============================================================================

/// Opaque LLM handle (wraps MNN::Transformer::Llm)
typedef void *MNNR_LLM;

/// Callback for streaming token output
typedef void (*MNNR_TokenCallback)(const char *token, void *user_data);

/**
 * Create LLM from config directory
 *
 * @param config_path Path to config.json file in model directory
 * @param error_code Output error code (can be NULL)
 * @return LLM handle or NULL on error
 */
MNNR_EXPORT MNNR_LLM mnnr_llm_create(const char *config_path,
                                     int32_t *error_code);

/**
 * Load the LLM model
 *
 * @param llm LLM handle
 * @return MNNR_SUCCESS or error code
 */
MNNR_EXPORT uint32_t mnnr_llm_load(MNNR_LLM llm);

/**
 * Destroy LLM and free resources
 *
 * @param llm LLM handle (safe to pass NULL)
 */
MNNR_EXPORT void mnnr_llm_destroy(MNNR_LLM llm);

/**
 * Generate response for a prompt (blocking, collects full response)
 *
 * @param llm LLM handle
 * @param prompt Input prompt text
 * @param output Buffer to receive output (null-terminated)
 * @param output_size Size of output buffer
 * @param max_tokens Maximum tokens to generate (0 for model default)
 * @return Number of characters written, or 0 on error
 */
MNNR_EXPORT size_t mnnr_llm_generate(MNNR_LLM llm, const char *prompt,
                                     char *output, size_t output_size,
                                     int32_t max_tokens);

/**
 * Generate response with streaming callback
 *
 * @param llm LLM handle
 * @param prompt Input prompt text
 * @param callback Function called for each token
 * @param user_data User data passed to callback
 * @param max_tokens Maximum tokens to generate (0 for model default)
 * @return MNNR_SUCCESS or error code
 */
MNNR_EXPORT uint32_t mnnr_llm_generate_stream(MNNR_LLM llm, const char *prompt,
                                              MNNR_TokenCallback callback,
                                              void *user_data,
                                              int32_t max_tokens);

/**
 * Reset LLM state (clear KV cache and history)
 *
 * @param llm LLM handle
 */
MNNR_EXPORT void mnnr_llm_reset(MNNR_LLM llm);

/**
 * Cancel ongoing generation
 * 
 * @param llm LLM handle
 */
MNNR_EXPORT void mnnr_llm_cancel(MNNR_LLM llm);

/**
 * Check if LLM has finished generating
 *
 * @param llm LLM handle
 * @return 1 if stopped, 0 if still generating
 */
MNNR_EXPORT int32_t mnnr_llm_stopped(MNNR_LLM llm);

/**
 * Get LLM performance metrics
 *
 * @param llm LLM handle
 * @param prompt_tokens Output: number of prompt tokens processed
 * @param gen_tokens Output: number of tokens generated
 * @param prefill_us Output: prefill time in microseconds
 * @param decode_us Output: decode time in microseconds
 */
void mnnr_llm_get_stats(MNNR_LLM llm, int32_t *prompt_tokens,
                        int32_t *gen_tokens, int64_t *prefill_us,
                        int64_t *decode_us);

/**
 * Set LLM config (sampling parameters, etc.)
 *
 * @param llm LLM handle
 * @param config_json JSON string with config overrides
 */
MNNR_EXPORT void mnnr_llm_set_config(MNNR_LLM llm, const char *config_json);

/**
 * Get memory usage of LLM
 *
 * @param llm LLM handle
 * @return Memory usage in bytes
 */
MNNR_EXPORT size_t mnnr_get_memory_usage_llm(MNNR_LLM llm);

// Legacy LLM operations (raw engine-based) - kept for compatibility
/**
 * Run prefill phase for LLM (process prompt tokens)
 *
 * @param engine Engine handle
 * @param token_ids Array of token IDs
 * @param num_tokens Number of tokens
 * @param logits Output logits buffer
 * @param vocab_size Vocabulary size
 * @return MNNR_SUCCESS or error code
 */
uint32_t mnnr_llm_prefill(MNNR_Engine engine, const int32_t *token_ids,
                          size_t num_tokens, float *logits, size_t vocab_size);

/**
 * Run decode phase for LLM (generate single token)
 *
 * @param engine Engine handle
 * @param token_id Previous token ID
 * @param logits Output logits buffer
 * @param vocab_size Vocabulary size
 * @return MNNR_SUCCESS or error code
 */
uint32_t mnnr_llm_decode(MNNR_Engine engine, int32_t token_id, float *logits,
                         size_t vocab_size);

/**
 * Clear KV cache for LLM
 *
 * @param engine Engine handle
 */
void mnnr_llm_clear_cache(MNNR_Engine engine);

/**
 * Get current KV cache length
 *
 * @param engine Engine handle
 * @return Current sequence length in cache
 */
MNNR_EXPORT size_t mnnr_llm_cache_length(MNNR_Engine engine);

// =============================================================================
// Embedding Operations (using MNN Transformer Embedding API)
// =============================================================================

/// Opaque Embedding handle (wraps MNN::Transformer::Embedding)
typedef void *MNNR_Embedding;

/**
 * Create Embedding engine from config directory
 *
 * @param config_path Path to model directory (containing config.json)
 * @param error_code Output error code
 * @return Embedding handle or NULL on error
 */
MNNR_EXPORT MNNR_Embedding mnnr_embedding_create(const char *config_path,
                                                 int32_t *error_code);

/**
 * Load the Embedding model
 *
 * @param embedding Embedding handle
 * @return MNNR_SUCCESS or error code
 */
MNNR_EXPORT uint32_t mnnr_embedding_load(MNNR_Embedding embedding);

/**
 * Destroy Embedding engine
 *
 * @param embedding Embedding handle
 */
MNNR_EXPORT void mnnr_embedding_destroy(MNNR_Embedding embedding);

/**
 * Generate embedding for text
 *
 * @param embedding Embedding handle
 * @param text Input text
 * @param output Output buffer for float vector
 * @param output_size Number of floats in output buffer
 * @return Number of floats written, or 0 on error
 */
MNNR_EXPORT size_t mnnr_embedding_generate(MNNR_Embedding embedding,
                                           const char *text, float *output,
                                           size_t output_size);

/**
 * Get embedding dimension
 *
 * @param embedding Embedding handle
 * @return Dimension or 0 on error
 */
MNNR_EXPORT int32_t mnnr_embedding_dim(MNNR_Embedding embedding);

#ifdef __cplusplus
}
#endif

#endif /* MNN_WRAPPER_H */
