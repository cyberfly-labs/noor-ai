/**
 * MNN C Wrapper Implementation for EdgeMind
 *
 * Implements the C API wrapper around MNN for safe FFI access from Rust.
 * Based on patterns from cyberfly-labs/kidance implementation.
 */

#include <cstdio>

#if defined(ANDROID)
#include <android/log.h>
#define LOG_TAG "mnnr_native"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...)                                                             \
  do {                                                                        \
    std::fprintf(stderr, "[INFO] mnnr_native: ");                            \
    std::fprintf(stderr, __VA_ARGS__);                                        \
    std::fprintf(stderr, "\n");                                             \
  } while (0)
#define LOGW(...)                                                             \
  do {                                                                        \
    std::fprintf(stderr, "[WARN] mnnr_native: ");                            \
    std::fprintf(stderr, __VA_ARGS__);                                        \
    std::fprintf(stderr, "\n");                                             \
  } while (0)
#define LOGE(...)                                                             \
  do {                                                                        \
    std::fprintf(stderr, "[ERROR] mnnr_native: ");                           \
    std::fprintf(stderr, __VA_ARGS__);                                        \
    std::fprintf(stderr, "\n");                                             \
  } while (0)
#endif

#include "mnn_wrapper.h"

// Only compile actual implementation when MNN is available
#if defined(MNN_AVAILABLE)

#include <MNN/Interpreter.hpp>
#include <MNN/MNNDefine.h>
#include <MNN/Tensor.hpp>
#include <MNN/expr/Executor.hpp>

// LLM support (if MNN_BUILD_LLM is enabled)
#if defined(MNN_BUILD_LLM) || defined(MNN_LLM_SUPPORT)
#include "llm/llm.hpp"
#define HAS_MNN_LLM 1
#else
#define HAS_MNN_LLM 0
#endif

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cmath>
#include <cstring>
#include <cstdlib>
#if defined(__ARM_NEON)
#include <arm_neon.h>
#endif
#include <memory>
#include <mutex>
#include <queue>
#include <sstream>
#include <string>
#include <unistd.h>
#include <unordered_map>
#include <vector>

#include "rapidjson/document.h"

static bool mnnr_timing_enabled() {
  static const bool enabled = []() {
    const char *env = std::getenv("EDGEMIND_TIMING");
    if (!env) {
      return false;
    }
    return std::strcmp(env, "1") == 0 || std::strcmp(env, "true") == 0 ||
           std::strcmp(env, "TRUE") == 0 || std::strcmp(env, "on") == 0 ||
           std::strcmp(env, "ON") == 0;
  }();
  return enabled;
}

// =============================================================================
// Internal Types
// =============================================================================

struct MNNREngine {
  std::unique_ptr<MNN::Interpreter> interpreter;
  MNN::Session *session = nullptr;
  MNN::Tensor *input_tensor = nullptr;
  MNN::Tensor *output_tensor = nullptr;
  MNN::ScheduleConfig schedule_config;
  MNN::BackendConfig backend_config; // Store here to ensure lifetime
  std::vector<int> input_shape;
  std::vector<int> output_shape;
  std::recursive_mutex mutex; // Add recursive mutex for thread safety

  // LLM-specific
  size_t kv_cache_len = 0;

  ~MNNREngine() {
    if (interpreter && session) {
      interpreter->releaseSession(session);
    }
  }
};

struct MNNRSessionPool {
  std::unique_ptr<MNN::Interpreter> interpreter;
  std::queue<MNN::Session *> available_sessions;
  std::vector<MNN::Session *> all_sessions;
  std::mutex mutex;
  MNN::ScheduleConfig schedule_config;
  MNN::BackendConfig backend_config; // Store here to ensure lifetime

  ~MNNRSessionPool() {
    for (auto *session : all_sessions) {
      interpreter->releaseSession(session);
    }
  }
};

// =============================================================================
// Helper Functions
// =============================================================================

static void configure_schedule(MNN::ScheduleConfig &schedule,
                               MNN::BackendConfig &backend_config,
                               const MNNR_Config *config) {
  schedule.numThread = config->thread_count;

  // Map backend type
  switch (config->backend) {
  case MNNR_BACKEND_METAL:
    // schedule.type = MNN_FORWARD_METAL; // Temporarily disabled for stability
    schedule.type = MNN_FORWARD_CPU;
    break;
  case MNNR_BACKEND_OPENCL:
    // schedule.type = MNN_FORWARD_OPENCL; // Temporarily disabled for stability
    schedule.type = MNN_FORWARD_CPU;
    break;
  case MNNR_BACKEND_VULKAN:
    // schedule.type = MNN_FORWARD_VULKAN; // Temporarily disabled for stability
    schedule.type = MNN_FORWARD_CPU;
    break;
  case MNNR_BACKEND_NNAPI:
    // schedule.type = MNN_FORWARD_NN; // Temporarily disabled for stability
    schedule.type = MNN_FORWARD_CPU;
    break;
  case MNNR_BACKEND_COREML:
    // schedule.type = MNN_FORWARD_USER_0; // Temporarily disabled for stability
    schedule.type = MNN_FORWARD_CPU;
    break;
  case MNNR_BACKEND_CPU:
  default:
    schedule.type = MNN_FORWARD_CPU;
    break;
  }

  // Configure backend
  switch (config->precision) {
  case MNNR_PRECISION_HIGH:
    backend_config.precision = MNN::BackendConfig::Precision_High;
    break;
  case MNNR_PRECISION_LOW:
  case MNNR_PRECISION_LOW_BF16:
    backend_config.precision = MNN::BackendConfig::Precision_Low;
    break;
  case MNNR_PRECISION_NORMAL:
  default:
    backend_config.precision = MNN::BackendConfig::Precision_Normal;
    break;
  }

  schedule.backendConfig = &backend_config;
}

extern "C" {
// =============================================================================
// Version & Info
// =============================================================================

const char *mnnr_get_version(void) {
  static std::string version = MNN_VERSION;
  return version.c_str();
}

int mnnr_is_available(void) { return 1; }

// =============================================================================
// Engine Operations
// =============================================================================

// =============================================================================
// Engine Operations
// =============================================================================

// =============================================================================
// Engine Operations
// =============================================================================

// Helper for named input access
void *mnnr_get_session_input(MNNR_Engine engine, const char *name) {
  if (!engine)
    return nullptr;
  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);

  // If name is null, return the default input tensor (first one)
  // If we already cached it in mnnr_create_engine and name is null, return that
  if (!name && eng->input_tensor) {
    return eng->input_tensor->host<void>();
  }

  auto tensor = eng->interpreter->getSessionInput(eng->session, name);
  if (!tensor)
    return nullptr;

  return tensor->host<void>();
}

uint32_t mnnr_get_session_input_info(MNNR_Engine engine, const char *name,
                                     int32_t *shape, int32_t *ndim) {
  if (!engine || !shape || !ndim)
    return MNNR_ERROR_INVALID_PARAM;
  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);

  auto tensor = eng->interpreter->getSessionInput(eng->session, name);
  if (!tensor)
    return MNNR_ERROR_RUNTIME; // Or NOT_FOUND

  auto dims = tensor->shape();
  *ndim = (int32_t)dims.size();
  for (size_t i = 0; i < dims.size() && i < 8; ++i) {
    shape[i] = dims[i];
  }
  return MNNR_SUCCESS;
}

uint32_t mnnr_resize_session_input(MNNR_Engine engine, const char *name,
                                   const int32_t *shape, int32_t ndim) {
  if (!engine || !shape || ndim <= 0)
    return MNNR_ERROR_INVALID_PARAM;
  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);

  auto tensor = eng->interpreter->getSessionInput(eng->session, name);
  if (!tensor)
    return MNNR_ERROR_RUNTIME;

  std::vector<int> new_shape(shape, shape + ndim);
  eng->interpreter->resizeTensor(tensor, new_shape);
  eng->interpreter->resizeSession(eng->session);

  // If this happened to be the default input, update the cached shape
  if (eng->input_tensor == tensor) {
    eng->input_shape = new_shape;
  }
  return MNNR_SUCCESS;
}

void *mnnr_get_session_output(MNNR_Engine engine, const char *name) {
  if (!engine)
    return nullptr;
  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);

  // If name is null, return default output
  if (!name && eng->output_tensor) {
    return eng->output_tensor->host<void>();
  }

  auto tensor = eng->interpreter->getSessionOutput(eng->session, name);
  if (!tensor)
    return nullptr;

  return tensor->host<void>();
}

uint32_t mnnr_get_session_output_info(MNNR_Engine engine, const char *name,
                                      int32_t *shape, int32_t *ndim) {
  if (!engine || !shape || !ndim)
    return MNNR_ERROR_INVALID_PARAM;
  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);

  auto tensor = eng->interpreter->getSessionOutput(eng->session, name);
  if (!tensor)
    return MNNR_ERROR_RUNTIME;

  auto dims = tensor->shape();
  *ndim = (int32_t)dims.size();
  for (size_t i = 0; i < dims.size() && i < 8; ++i) {
    shape[i] = dims[i];
  }
  return MNNR_SUCCESS;
}

MNNR_Engine mnnr_create_engine(const char *model_path,
                               const MNNR_Config *config, int32_t *error_code) {

  if (!model_path || !config) {
    if (error_code)
      *error_code = MNNR_ERROR_INVALID_PARAM;
    return nullptr;
  }

  auto engine = new MNNREngine();

  // Load interpreter
  engine->interpreter.reset(MNN::Interpreter::createFromFile(model_path));
  if (!engine->interpreter) {
    if (error_code)
      *error_code = MNNR_ERROR_MODEL_LOAD_FAILED;
    delete engine;
    return nullptr;
  }

  // Configure schedule and backend_config
  configure_schedule(engine->schedule_config, engine->backend_config, config);

  // Create session
  engine->session = engine->interpreter->createSession(engine->schedule_config);
  if (!engine->session) {
    if (error_code)
      *error_code = MNNR_ERROR_RUNTIME;
    delete engine;
    return nullptr;
  }

  // Get input/output tensors
  engine->input_tensor =
      engine->interpreter->getSessionInput(engine->session, nullptr);
  engine->output_tensor =
      engine->interpreter->getSessionOutput(engine->session, nullptr);

  // Note: For multi-input models (like MiniLM), input_tensor might be null if
  // accessed without name We don't enforce null check here for input/output to
  // allow flexible named access later.

  if (engine->input_tensor) {
    auto input_dims = engine->input_tensor->shape();
    engine->input_shape.assign(input_dims.begin(), input_dims.end());
  }

  if (engine->output_tensor) {
    auto output_dims = engine->output_tensor->shape();
    engine->output_shape.assign(output_dims.begin(), output_dims.end());
  }

  if (error_code)
    *error_code = MNNR_SUCCESS;
  return engine;
}

MNNR_Engine mnnr_create_engine_from_buffer(const void *buffer,
                                           size_t buffer_size,
                                           const MNNR_Config *config,
                                           int32_t *error_code) {
  if (!buffer || buffer_size == 0 || !config) {
    if (error_code)
      *error_code = MNNR_ERROR_INVALID_PARAM;
    return nullptr;
  }

  auto engine = new MNNREngine();

  // Load interpreter from buffer
  engine->interpreter.reset(
      MNN::Interpreter::createFromBuffer(buffer, buffer_size));
  if (!engine->interpreter) {
    if (error_code)
      *error_code = MNNR_ERROR_MODEL_LOAD_FAILED;
    delete engine;
    return nullptr;
  }

  // Configure schedule and backend_config
  configure_schedule(engine->schedule_config, engine->backend_config, config);

  // Create session
  engine->session = engine->interpreter->createSession(engine->schedule_config);
  if (!engine->session) {
    if (error_code)
      *error_code = MNNR_ERROR_RUNTIME;
    delete engine;
    return nullptr;
  }

  // Get input/output tensors
  engine->input_tensor =
      engine->interpreter->getSessionInput(engine->session, nullptr);
  engine->output_tensor =
      engine->interpreter->getSessionOutput(engine->session, nullptr);

  if (engine->input_tensor) {
    auto input_dims = engine->input_tensor->shape();
    engine->input_shape.assign(input_dims.begin(), input_dims.end());
  }

  if (engine->output_tensor) {
    auto output_dims = engine->output_tensor->shape();
    engine->output_shape.assign(output_dims.begin(), output_dims.end());
  }

  if (error_code)
    *error_code = MNNR_SUCCESS;
  return engine;
}

void mnnr_destroy_engine(MNNR_Engine engine) {
  if (engine) {
    delete static_cast<MNNREngine *>(engine);
  }
}

// Helper to copy data handling type safety
static void copy_to_input_tensor(MNN::Tensor *tensor, const void *input_data,
                                 size_t element_count) {
  auto type = tensor->getType();
  if (type.code == halide_type_int) {
    if (type.bits == 32) {
      auto *ptr = tensor->host<int32_t>();
      // If input is float (legacy API), we might have issues here.
      // But mnnr_run_inference assumes float input.
      // Ideally we need typed APIs. For now, assuming float input and casting
      // if needed for Int32 inputs WARNING: This assumes input_data is float*
      // if calling mnnr_run_inference Use mnnr_interpreter_get_input_tensor for
      // direct typed access.
      const float *src = static_cast<const float *>(input_data);
      for (size_t i = 0; i < element_count; ++i)
        ptr[i] = (int32_t)src[i];
    } else if (type.bits == 64) {
      auto *ptr = tensor->host<int64_t>();
      const float *src = static_cast<const float *>(input_data);
      for (size_t i = 0; i < element_count; ++i)
        ptr[i] = (int64_t)src[i];
    }
  } else if (type.code == halide_type_float) {
    auto *ptr = tensor->host<float>();
    std::memcpy(ptr, input_data, element_count * sizeof(float));
  }
}

uint32_t mnnr_run_inference(MNNR_Engine engine, const float *input,
                            size_t input_size, float *output,
                            size_t output_size) {
  if (!engine || !input || !output) {
    return MNNR_ERROR_INVALID_PARAM;
  }

  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);

  if (!eng->input_tensor || !eng->output_tensor) {
    // Trying to run simple inference engine without default tensors
    return MNNR_ERROR_RUNTIME;
  }

  // Copy input data with type handling
  copy_to_input_tensor(eng->input_tensor, input, input_size);

  // Run inference
  auto error_code = eng->interpreter->runSession(eng->session);
  if (error_code != MNN::NO_ERROR) {
    return MNNR_ERROR_RUNTIME;
  }

  // Copy output data
  auto output_host = eng->output_tensor->host<float>();
  size_t copy_size =
      std::min(output_size, (size_t)eng->output_tensor->elementSize());
  std::memcpy(output, output_host, copy_size * sizeof(float));

  return MNNR_SUCCESS;
}

// =============================================================================
// Shape Operations
// =============================================================================

uint32_t mnnr_get_input_shape(MNNR_Engine engine, int32_t index, int32_t *shape,
                              int32_t *ndim) {
  if (!engine || !shape || !ndim) {
    return MNNR_ERROR_INVALID_PARAM;
  }

  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);
  *ndim = (int32_t)eng->input_shape.size();

  for (size_t i = 0; i < eng->input_shape.size(); i++) {
    shape[i] = eng->input_shape[i];
  }

  return MNNR_SUCCESS;
}

uint32_t mnnr_get_output_shape(MNNR_Engine engine, int32_t index,
                               int32_t *shape, int32_t *ndim) {
  if (!engine || !shape || !ndim) {
    return MNNR_ERROR_INVALID_PARAM;
  }

  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);
  *ndim = (int32_t)eng->output_shape.size();

  for (size_t i = 0; i < eng->output_shape.size(); i++) {
    shape[i] = eng->output_shape[i];
  }

  return MNNR_SUCCESS;
}

uint32_t mnnr_resize_input(MNNR_Engine engine, int32_t index,
                           const int32_t *shape, int32_t ndim) {
  if (!engine || !shape || ndim <= 0) {
    return MNNR_ERROR_INVALID_PARAM;
  }

  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);

  std::vector<int> new_shape(shape, shape + ndim);
  eng->interpreter->resizeTensor(eng->input_tensor, new_shape);
  eng->interpreter->resizeSession(eng->session);

  eng->input_shape = new_shape;

  return MNNR_SUCCESS;
}

// =============================================================================
// Session Pool Operations
// =============================================================================

MNNR_SessionPool mnnr_create_session_pool(const char *model_path,
                                          const MNNR_Config *config,
                                          int32_t pool_size) {
  if (!model_path || !config || pool_size <= 0) {
    return nullptr;
  }

  auto pool = new MNNRSessionPool();

  // Load interpreter
  pool->interpreter.reset(MNN::Interpreter::createFromFile(model_path));
  if (!pool->interpreter) {
    delete pool;
    return nullptr;
  }

  // Configure schedule and backend_config
  configure_schedule(pool->schedule_config, pool->backend_config, config);

  // Create sessions
  for (int i = 0; i < pool_size; i++) {
    auto *session = pool->interpreter->createSession(pool->schedule_config);
    if (session) {
      pool->all_sessions.push_back(session);
      pool->available_sessions.push(session);
    }
  }

  if (pool->all_sessions.empty()) {
    delete pool;
    return nullptr;
  }

  return pool;
}

void mnnr_destroy_session_pool(MNNR_SessionPool pool) {
  if (pool) {
    delete static_cast<MNNRSessionPool *>(pool);
  }
}

uint32_t mnnr_pool_run_inference(MNNR_SessionPool pool, const float *input,
                                 size_t input_size, float *output,
                                 size_t output_size) {
  if (!pool || !input || !output) {
    return MNNR_ERROR_INVALID_PARAM;
  }

  auto *p = static_cast<MNNRSessionPool *>(pool);

  // Acquire session
  MNN::Session *session = nullptr;
  {
    std::lock_guard<std::mutex> lock(p->mutex);
    if (p->available_sessions.empty()) {
      return MNNR_ERROR_RUNTIME; // No sessions available
    }
    session = p->available_sessions.front();
    p->available_sessions.pop();
  }

  // Get tensors
  auto *input_tensor = p->interpreter->getSessionInput(session, nullptr);
  auto *output_tensor = p->interpreter->getSessionOutput(session, nullptr);

  // Copy input
  auto input_host = input_tensor->host<float>();
  std::memcpy(input_host, input, input_size * sizeof(float));

  // Run inference
  auto error_code = p->interpreter->runSession(session);

  // Copy output
  auto output_host = output_tensor->host<float>();
  size_t copy_size =
      std::min(output_size, (size_t)output_tensor->elementSize());
  std::memcpy(output, output_host, copy_size * sizeof(float));

  // Release session
  {
    std::lock_guard<std::mutex> lock(p->mutex);
    p->available_sessions.push(session);
  }

  return error_code == MNN::NO_ERROR ? MNNR_SUCCESS : MNNR_ERROR_RUNTIME;
}

int32_t mnnr_pool_available_sessions(MNNR_SessionPool pool) {
  if (!pool)
    return 0;

  auto *p = static_cast<MNNRSessionPool *>(pool);
  std::lock_guard<std::mutex> lock(p->mutex);
  return (int32_t)p->available_sessions.size();
}

// =============================================================================
// Interpreter Operations
// =============================================================================

MNNR_Interpreter mnnr_interpreter_create_from_file(const char *model_path) {
  if (!model_path)
    return nullptr;
  return MNN::Interpreter::createFromFile(model_path);
}

MNNR_Interpreter mnnr_interpreter_create_from_buffer(const void *buffer,
                                                     size_t size) {
  if (!buffer || size == 0)
    return nullptr;
  return MNN::Interpreter::createFromBuffer(buffer, size);
}

void mnnr_interpreter_destroy(MNNR_Interpreter interpreter) {
  if (interpreter) {
    delete static_cast<MNN::Interpreter *>(interpreter);
  }
}

MNNR_Session mnnr_interpreter_create_session(MNNR_Interpreter interpreter,
                                             const MNNR_Config *config) {
  if (!interpreter || !config)
    return nullptr;

  auto *interp = static_cast<MNN::Interpreter *>(interpreter);
  MNN::ScheduleConfig schedule;
  MNN::BackendConfig backend_config;
  configure_schedule(schedule, backend_config, config);

  return interp->createSession(schedule);
}

uint32_t mnnr_interpreter_run(MNNR_Interpreter interpreter,
                              MNNR_Session session) {
  if (!interpreter || !session)
    return MNNR_ERROR_INVALID_PARAM;

  auto *interp = static_cast<MNN::Interpreter *>(interpreter);
  auto *sess = static_cast<MNN::Session *>(session);

  auto code = interp->runSession(sess);
  return code == MNN::NO_ERROR ? MNNR_SUCCESS : MNNR_ERROR_RUNTIME;
}

void mnnr_interpreter_resize_session(MNNR_Interpreter interpreter,
                                     MNNR_Session session) {
  if (!interpreter || !session)
    return;

  auto *interp = static_cast<MNN::Interpreter *>(interpreter);
  auto *sess = static_cast<MNN::Session *>(session);

  interp->resizeSession(sess);
}

void mnnr_interpreter_resize_input(MNNR_Interpreter interpreter,
                                   MNNR_Session session, const char *name,
                                   const int32_t *shape, int32_t ndim) {
  if (!interpreter || !session || !shape || ndim <= 0)
    return;

  auto *interp = static_cast<MNN::Interpreter *>(interpreter);
  auto *sess = static_cast<MNN::Session *>(session);

  auto *tensor = interp->getSessionInput(sess, name);
  if (tensor) {
    std::vector<int> new_shape(shape, shape + ndim);
    interp->resizeTensor(tensor, new_shape);
  }
}

void *mnnr_interpreter_get_input_tensor(MNNR_Interpreter interpreter,
                                        MNNR_Session session, const char *name,
                                        int32_t *shape, int32_t *ndim) {
  if (!interpreter || !session || !shape || !ndim)
    return nullptr;

  auto *interp = static_cast<MNN::Interpreter *>(interpreter);
  auto *sess = static_cast<MNN::Session *>(session);

  auto *tensor = interp->getSessionInput(sess, name);
  if (!tensor)
    return nullptr;

  auto dims = tensor->shape();
  *ndim = (int32_t)dims.size();
  for (size_t i = 0; i < dims.size() && i < 8; i++) {
    shape[i] = dims[i];
  }

  // Return raw pointer to host memory
  // Note: Assuming tensor is on host or mapped
  return tensor->host<void>();
}

void *mnnr_interpreter_get_output_tensor(MNNR_Interpreter interpreter,
                                         MNNR_Session session, const char *name,
                                         int32_t *shape, int32_t *ndim) {
  if (!interpreter || !session || !shape || !ndim)
    return nullptr;

  auto *interp = static_cast<MNN::Interpreter *>(interpreter);
  auto *sess = static_cast<MNN::Session *>(session);

  auto *tensor = interp->getSessionOutput(sess, name);
  if (!tensor)
    return nullptr;

  auto dims = tensor->shape();
  *ndim = (int32_t)dims.size();
  for (size_t i = 0; i < dims.size() && i < 8; i++) {
    shape[i] = dims[i];
  }

  // For output, user needs to copy or access
  return tensor->host<void>();
}

void mnnr_set_global_executor_config(int32_t num_threads, int32_t backend) {
  // Use BackendConfig (from MNNForwardType.h) for executor configuration
  MNN::BackendConfig backendConfig;
  backendConfig.precision =
      MNN::BackendConfig::Precision_Low; // FP16 for performance
  backendConfig.power = MNN::BackendConfig::Power_High;

  MNNForwardType forwardType = MNN_FORWARD_CPU;
  switch (backend) {
  case MNNR_BACKEND_OPENCL:
    forwardType = MNN_FORWARD_OPENCL;
    break;
  case MNNR_BACKEND_VULKAN:
    forwardType = MNN_FORWARD_VULKAN;
    break;
  case MNNR_BACKEND_METAL:
    forwardType = MNN_FORWARD_METAL;
    break;
  case MNNR_BACKEND_NNAPI:
    forwardType = MNN_FORWARD_NN;
    break;
  case MNNR_BACKEND_COREML:
    forwardType = MNN_FORWARD_USER_0;
    break;
  default:
    forwardType = MNN_FORWARD_CPU;
    break;
  }

  // Use the correct API: getGlobalExecutor()->setGlobalExecutorConfig()
  MNN::Express::Executor::getGlobalExecutor()->setGlobalExecutorConfig(
      forwardType, backendConfig, num_threads);
}

// =============================================================================
// Memory Management
// =============================================================================

size_t mnnr_get_memory_usage(MNNR_Engine engine) {
  if (!engine)
    return 0;

  auto *eng = static_cast<MNNREngine *>(engine);
  float memory_mb = 0.0f;
  eng->interpreter->getSessionInfo(eng->session, MNN::Interpreter::MEMORY,
                                   &memory_mb);
  return static_cast<size_t>(memory_mb * 1024 * 1024); // Convert MB to bytes
}

void mnnr_release_cache(MNNR_Engine engine) {
  if (!engine)
    return;

  auto *eng = static_cast<MNNREngine *>(engine);
  eng->interpreter->releaseModel();
}

// =============================================================================
// LLM-Specific Operations
// =============================================================================

uint32_t mnnr_llm_prefill(MNNR_Engine engine, const int32_t *token_ids,
                          size_t num_tokens, float *logits, size_t vocab_size) {
  if (!engine || !token_ids || !logits || num_tokens == 0 || vocab_size == 0) {
    return MNNR_ERROR_INVALID_PARAM;
  }

  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);

  if (!eng->interpreter || !eng->session || !eng->input_tensor ||
      !eng->output_tensor) {
    return MNNR_ERROR_NULL_POINTER;
  }

  // Resize input for prefill
  std::vector<int> new_shape = {1, (int)num_tokens};
  eng->interpreter->resizeTensor(eng->input_tensor, new_shape);
  eng->interpreter->resizeSession(eng->session);

  // Verify tensor host is available
  auto input_host = eng->input_tensor->host<float>();
  if (!input_host) {
    return MNNR_ERROR_NULL_POINTER;
  }

  // Copy token IDs (convert to float for MNN)
  for (size_t i = 0; i < num_tokens; i++) {
    input_host[i] = (float)token_ids[i];
  }

  // Run inference
  auto error_code = eng->interpreter->runSession(eng->session);
  if (error_code != MNN::NO_ERROR) {
    return MNNR_ERROR_RUNTIME;
  }

  // Verify output is available
  auto output_host = eng->output_tensor->host<float>();
  if (!output_host) {
    return MNNR_ERROR_NULL_POINTER;
  }

  // Copy output logits (last position only)
  size_t output_offset = (num_tokens - 1) * vocab_size;
  std::memcpy(logits, output_host + output_offset, vocab_size * sizeof(float));

  // Update cache length
  eng->kv_cache_len = num_tokens;

  return MNNR_SUCCESS;
}

uint32_t mnnr_llm_decode(MNNR_Engine engine, int32_t token_id, float *logits,
                         size_t vocab_size) {
  if (!engine || !logits) {
    return MNNR_ERROR_INVALID_PARAM;
  }

  auto *eng = static_cast<MNNREngine *>(engine);
  std::lock_guard<std::recursive_mutex> lock(eng->mutex);

  // Resize input for single token decode if needed
  if (eng->input_shape.size() != 2 || eng->input_shape[0] != 1 ||
      eng->input_shape[1] != 1) {
    std::vector<int> new_shape = {1, 1};
    eng->interpreter->resizeTensor(eng->input_tensor, new_shape);
    eng->interpreter->resizeSession(eng->session);
    eng->input_shape = new_shape;
  }

  // Set input token
  auto input_host = eng->input_tensor->host<float>();
  input_host[0] = (float)token_id;

  // Run inference
  auto error_code = eng->interpreter->runSession(eng->session);
  if (error_code != MNN::NO_ERROR) {
    return MNNR_ERROR_RUNTIME;
  }

  // Copy output logits
  auto output_host = eng->output_tensor->host<float>();
  std::memcpy(logits, output_host, vocab_size * sizeof(float));

  // Update cache length
  eng->kv_cache_len++;

  return MNNR_SUCCESS;
}

void mnnr_llm_clear_cache(MNNR_Engine engine) {
  if (!engine)
    return;

  auto *eng = static_cast<MNNREngine *>(engine);
  eng->kv_cache_len = 0;
  // Note: Actual KV cache clearing depends on model implementation
}

size_t mnnr_llm_cache_length(MNNR_Engine engine) {
  if (!engine)
    return 0;

  auto *eng = static_cast<MNNREngine *>(engine);
  return eng->kv_cache_len;
}

// =============================================================================
// MNN Transformer LLM API Implementation
// =============================================================================

#if HAS_MNN_LLM

struct MNNRLlm {
  MNN::Transformer::Llm *llm = nullptr;
  std::string last_response;
  std::mutex mutex;
  std::atomic<bool> cancelled{false};

  ~MNNRLlm() {
    std::lock_guard<std::mutex> lock(mutex);
    if (llm) {
      delete llm;
    }
  }
};

struct MNNREmbedding {
  MNN::Transformer::Embedding *embedding = nullptr;
  std::mutex mutex;

  // --- New Interpreter-based fields ---
  std::unique_ptr<MNN::Interpreter> interpreter;
  MNN::Session *session = nullptr;
  MNN::ScheduleConfig schedule_config;
  MNN::BackendConfig backend_config;
  // Tokenizer: vocab mapping (token string -> id)
  std::unordered_map<std::string, int> vocab;
  int cls_id = 101;
  int sep_id = 102;
  int unk_id = 100;
  int pad_id = 0;
  std::string continuing_prefix = "##";
  int max_input_chars = 100;
  int embedding_dim = 384;
  int last_seq_len = -1; // caching seq len for faster resizeSession
  std::string model_dir; // directory containing model.mnn and tokenizer.json

  // Reusable host tensors to prevent memory heap thrashing (#1 review feedback)
  std::unique_ptr<MNN::Tensor> host_input_ids;
  std::unique_ptr<MNN::Tensor> host_attention_mask;
  std::unique_ptr<MNN::Tensor> host_token_type_ids;
  std::unique_ptr<MNN::Tensor> host_output;

  ~MNNREmbedding() {
    std::lock_guard<std::mutex> lock(mutex);
    if (session && interpreter) {
      interpreter->releaseSession(session);
    }
    // interpreter unique_ptr auto-deletes
    // Legacy path cleanup
    if (embedding) {
      delete embedding;
    }
  }
};

// =============================================================================
// Simple BERT WordPiece Tokenizer (parses HuggingFace tokenizer.json)
// =============================================================================

static bool parse_tokenizer_json(const std::string &path, MNNREmbedding *emb) {
  FILE *f = fopen(path.c_str(), "r");
  if (!f) {
    LOGE("Cannot open tokenizer: %s", path.c_str());
    return false;
  }
  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);
  std::string json_str(sz, '\0');
  size_t bytes_read = fread(&json_str[0], 1, sz, f);
  fclose(f);

  if (bytes_read != (size_t)sz) {
    LOGE("Tokenizer file read truncated! Expected %ld bytes but got %zu", sz,
         bytes_read);
    return false;
  }

  // Use rapidjson to parse
  rapidjson::Document doc;
  doc.Parse(json_str.c_str());
  if (doc.HasParseError()) {
    LOGE("tokenizer.json parse error at offset %zu", doc.GetErrorOffset());
    return false;
  }

  // Extract vocab from model.vocab
  if (doc.HasMember("model") && doc["model"].IsObject()) {
    auto &model = doc["model"];
    if (model.HasMember("vocab")) {
      auto &vocab = model["vocab"];
      if (vocab.IsObject()) {
        for (auto it = vocab.MemberBegin(); it != vocab.MemberEnd(); ++it) {
          emb->vocab[it->name.GetString()] = it->value.GetInt();
        }
      } else if (vocab.IsArray()) {
        for (rapidjson::SizeType i = 0; i < vocab.Size(); i++) {
          auto &entry = vocab[i];
          if (entry.IsArray() && entry.Size() > 0 && entry[0].IsString()) {
            emb->vocab[entry[0].GetString()] = (int)i;
          } else if (entry.IsString()) {
            emb->vocab[entry.GetString()] = (int)i;
          }
        }
      }
    }

    if (model.HasMember("unk_token") && model["unk_token"].IsString()) {
      auto uit = emb->vocab.find(model["unk_token"].GetString());
      if (uit != emb->vocab.end())
        emb->unk_id = uit->second;
    }
    if (model.HasMember("continuing_subword_prefix") &&
        model["continuing_subword_prefix"].IsString()) {
      emb->continuing_prefix = model["continuing_subword_prefix"].GetString();
    }
  }

  // Fallback check in top-level added_tokens if missing from model vocab
  if (doc.HasMember("added_tokens") && doc["added_tokens"].IsArray()) {
    auto &added = doc["added_tokens"];
    for (rapidjson::SizeType i = 0; i < added.Size(); i++) {
      if (added[i].IsObject() && added[i].HasMember("content") &&
          added[i].HasMember("id")) {
        emb->vocab[added[i]["content"].GetString()] = added[i]["id"].GetInt();
      }
    }
  }

  // Find special token IDs
  auto find_id = [&](const std::vector<const char *> &candidates,
                     int fallback) -> int {
    for (auto tok : candidates) {
      auto it = emb->vocab.find(tok);
      if (it != emb->vocab.end())
        return it->second;
    }
    return fallback;
  };

  // Support BERT ([CLS]) and XLM-RoBERTa (<s>)
  emb->cls_id = find_id({"[CLS]", "<s>", "<s>"}, 101);
  emb->sep_id = find_id({"[SEP]", "</s>", "</s>"}, 102);
  emb->pad_id = find_id({"[PAD]", "<pad>", "<pad>"}, 0);
  emb->unk_id = find_id({"[UNK]", "<unk>", "<unk>"}, emb->unk_id);

  LOGI("Tokenizer loaded: %zu vocab entries, CLS=%d, SEP=%d, UNK=%d",
       emb->vocab.size(), emb->cls_id, emb->sep_id, emb->unk_id);
  return !emb->vocab.empty();
}

// Simple ASCII lowercase
static std::string to_lower(const std::string &s) {
  std::string out = s;
  for (auto &c : out) {
    if (c >= 'A' && c <= 'Z')
      c = c - 'A' + 'a';
  }
  return out;
}

// Check if character is punctuation
static bool is_punct(char c) {
  return (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) ||
         (c >= 123 && c <= 126);
}

// Split text into words (whitespace + punctuation split)
static std::vector<std::string> basic_tokenize(const std::string &text) {
  std::vector<std::string> tokens;
  std::string lower = to_lower(text);
  std::string current;
  for (char c : lower) {
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      if (!current.empty()) {
        tokens.push_back(current);
        current.clear();
      }
    } else if (is_punct(c)) {
      if (!current.empty()) {
        tokens.push_back(current);
        current.clear();
      }
      tokens.push_back(std::string(1, c));
    } else {
      current += c;
    }
  }
  if (!current.empty())
    tokens.push_back(current);
  return tokens;
}

// WordPiece tokenization for a single word
static std::vector<int>
wordpiece_tokenize(const std::string &word,
                   const std::unordered_map<std::string, int> &vocab,
                   const std::string &prefix, int unk_id, int max_chars) {
  if ((int)word.size() > max_chars) {
    return {unk_id};
  }

  std::vector<int> ids;
  int start = 0;
  while (start < (int)word.size()) {
    int end = (int)word.size();
    bool found = false;
    while (start < end) {
      std::string substr = word.substr(start, end - start);
      if (start > 0)
        substr = prefix + substr;
      auto it = vocab.find(substr);
      if (it != vocab.end()) {
        ids.push_back(it->second);
        found = true;
        break;
      }
      end--;
    }
    if (!found) {
      ids.push_back(unk_id);
      break;
    }
    start = end;
  }
  return ids;
}

// Full tokenization: text -> token IDs (with [CLS] and [SEP])
static std::vector<int> tokenize_text(const std::string &text,
                                      MNNREmbedding *emb, int max_len = 512) {
  auto words = basic_tokenize(text);
  std::vector<int> ids;
  ids.reserve(max_len);
  ids.push_back(emb->cls_id);
  for (auto &w : words) {
    auto wp_ids = wordpiece_tokenize(w, emb->vocab, emb->continuing_prefix,
                                     emb->unk_id, emb->max_input_chars);
    for (int id : wp_ids) {
      if ((int)ids.size() >= max_len - 1)
        break;
      ids.push_back(id);
    }
    if ((int)ids.size() >= max_len - 1)
      break;
  }
  ids.push_back(emb->sep_id);
  return ids;
}

// =============================================================================
// MNN Interpreter-based Embedding API Implementation
// (Ported from legacy Rust embedder.rs)
// =============================================================================

MNNR_Embedding mnnr_embedding_create(const char *config_path,
                                     int32_t *error_code) {
  LOGI("mnnr_embedding_create entry: config_path=%s",
       config_path ? config_path : "NULL");
  if (!config_path) {
    if (error_code)
      *error_code = MNNR_ERROR_INVALID_PARAM;
    return nullptr;
  }

  try {
    auto *wrapper = new MNNREmbedding();
    std::string path_str(config_path);

    // Ensure trailing slash for directory
    if (!path_str.empty() && path_str.back() != '/')
      path_str += '/';
    wrapper->model_dir = path_str;

    // Find model.mnn file
    std::string model_path;
    const char *preferred[] = {"embedding.mnn", "model.mnn", "llm.mnn"};
    for (auto name : preferred) {
      std::string candidate = path_str + name;
      if (access(candidate.c_str(), F_OK) == 0) {
        model_path = candidate;
        break;
      }
    }
    if (model_path.empty()) {
      LOGE("No .mnn model file found in %s", path_str.c_str());
      if (error_code)
        *error_code = MNNR_ERROR_MODEL_LOAD_FAILED;
      delete wrapper;
      return nullptr;
    }

    LOGI("Loading embedding model: %s", model_path.c_str());
    wrapper->interpreter.reset(
        MNN::Interpreter::createFromFile(model_path.c_str()));
    if (!wrapper->interpreter) {
      LOGE("Failed to create Interpreter from %s", model_path.c_str());
      if (error_code)
        *error_code = MNNR_ERROR_MODEL_LOAD_FAILED;
      delete wrapper;
      return nullptr;
    }

    // Load tokenizer
    std::string tokenizer_path = path_str + "tokenizer.json";
    if (!parse_tokenizer_json(tokenizer_path, wrapper)) {
      LOGE("Failed to load tokenizer from %s", tokenizer_path.c_str());
      if (error_code)
        *error_code = MNNR_ERROR_RUNTIME;
      delete wrapper;
      return nullptr;
    }

    if (error_code)
      *error_code = MNNR_SUCCESS;
    return wrapper;
  } catch (const std::exception &e) {
    LOGE("mnnr_embedding_create exception: %s", e.what());
    if (error_code)
      *error_code = MNNR_ERROR_RUNTIME;
    return nullptr;
  }
}

uint32_t mnnr_embedding_load(MNNR_Embedding embedding) {
  if (!embedding)
    return MNNR_ERROR_INVALID_PARAM;
  auto *wrapper = static_cast<MNNREmbedding *>(embedding);
  std::lock_guard<std::mutex> lock(wrapper->mutex);

  if (!wrapper->interpreter)
    return MNNR_ERROR_NULL_POINTER;

  // Create session
  wrapper->schedule_config.numThread = 4;
  wrapper->schedule_config.type = MNN_FORWARD_CPU;
  wrapper->backend_config.precision = MNN::BackendConfig::Precision_Low;
  wrapper->schedule_config.backendConfig = &wrapper->backend_config;

  wrapper->session =
      wrapper->interpreter->createSession(wrapper->schedule_config);
  if (!wrapper->session) {
    LOGE("Failed to create MNN session for embedding model");
    return MNNR_ERROR_RUNTIME;
  }

  // Enumerate ALL input tensors
  auto input_map = wrapper->interpreter->getSessionInputAll(wrapper->session);
  LOGI("=== Embedding model INPUT tensors (%zu) ===", input_map.size());
  for (auto &kv : input_map) {
    auto shape = kv.second->shape();
    std::string shape_str = "[";
    for (int i = 0; i < (int)shape.size(); i++) {
      if (i > 0)
        shape_str += ", ";
      shape_str += std::to_string(shape[i]);
    }
    shape_str += "]";
    LOGI("  INPUT: '%s' shape=%s", kv.first.c_str(), shape_str.c_str());
  }

  // Enumerate ALL output tensors
  auto output_map = wrapper->interpreter->getSessionOutputAll(wrapper->session);
  LOGI("=== Embedding model OUTPUT tensors (%zu) ===", output_map.size());
  for (auto &kv : output_map) {
    auto shape = kv.second->shape();
    std::string shape_str = "[";
    for (int i = 0; i < (int)shape.size(); i++) {
      if (i > 0)
        shape_str += ", ";
      shape_str += std::to_string(shape[i]);
    }
    shape_str += "]";
    LOGI("  OUTPUT: '%s' shape=%s", kv.first.c_str(), shape_str.c_str());
  }

  // Detect embedding dimension from output shape
  // Try common output tensor names
  const char *output_names[] = {"last_hidden_state", "embeddings",
                                "sentence_embedding", "output", nullptr};
  MNN::Tensor *out_tensor = nullptr;
  const char *found_output_name = nullptr;
  for (int i = 0; output_names[i]; i++) {
    out_tensor = wrapper->interpreter->getSessionOutput(wrapper->session,
                                                        output_names[i]);
    if (out_tensor) {
      found_output_name = output_names[i];
      LOGI("Found output tensor by name: '%s'", output_names[i]);
      break;
    }
  }
  // Also try unnamed (first output)
  if (!out_tensor) {
    out_tensor =
        wrapper->interpreter->getSessionOutput(wrapper->session, nullptr);
    if (out_tensor) {
      found_output_name = "(default/first)";
      LOGI("Using default (first) output tensor");
    }
  }

  if (out_tensor) {
    auto shape = out_tensor->shape();
    // Dim is last axis
    if (!shape.empty()) {
      int last_dim = shape.back();
      // Sometimes the initial shape has placeholder dims (-1 or 0)
      if (last_dim > 0 && last_dim < 10000) {
        wrapper->embedding_dim = last_dim;
      }
      LOGI("Output tensor '%s' last dim: %d, using embedding_dim=%d",
           found_output_name ? found_output_name : "?", last_dim,
           wrapper->embedding_dim);
    }
  } else {
    LOGW("No output tensor found during load - will retry during generate");
  }

  LOGI("Embedding model loaded successfully via Interpreter. Dim=%d",
       wrapper->embedding_dim);
  return MNNR_SUCCESS;
}

void mnnr_embedding_destroy(MNNR_Embedding embedding) {
  if (embedding) {
    delete static_cast<MNNREmbedding *>(embedding);
  }
}

size_t mnnr_embedding_generate(MNNR_Embedding embedding, const char *text,
                               float *output, size_t output_size) {
  if (!embedding || !text || !output)
    return 0;
  auto *wrapper = static_cast<MNNREmbedding *>(embedding);
  std::lock_guard<std::mutex> lock(wrapper->mutex);
  auto t0 = std::chrono::steady_clock::now();

  if (!wrapper->interpreter || !wrapper->session) {
    LOGE("embedding_generate: interpreter=%p session=%p",
         wrapper->interpreter.get(), wrapper->session);
    return 0;
  }

  try {
    // 1. Tokenize
    std::string text_str(text);
    auto token_ids = tokenize_text(text_str, wrapper, 512);
    int seq_len = (int)token_ids.size();

#ifdef DEBUG_EMBEDDING
    LOGI("embedding_generate: tokenized %d tokens from text len=%zu", seq_len,
         text_str.size());
#endif

    if (seq_len == 0)
      return 0;

#ifdef DEBUG_EMBEDDING
    // Log first few token IDs for debugging
    std::string id_str;
    for (int i = 0; i < std::min(seq_len, 10); i++) {
      if (i > 0)
        id_str += ", ";
      id_str += std::to_string(token_ids[i]);
    }
    if (seq_len > 10)
      id_str += "...";
    LOGI("embedding_generate: token_ids=[%s]", id_str.c_str());
#endif

    // Create attention mask (1 for real tokens, 0 for padding)
    std::vector<int> attention_mask(seq_len, 1);
    std::vector<int> token_type_ids(seq_len, 0);

    // 2. Resize input tensors (use cached seq len to bypass MNN thrashing)
    const int MAX_SEQ = 512;
    std::vector<int> shape = {1, MAX_SEQ};

    auto *input_ids_tensor =
        wrapper->interpreter->getSessionInput(wrapper->session, "input_ids");
    if (!input_ids_tensor) {
      LOGE("Cannot find input tensor 'input_ids'");
      return 0;
    }

#ifdef DEBUG_EMBEDDING
    LOGI("embedding_generate: found input_ids tensor, ensuring max size [1,%d]",
         MAX_SEQ);
#endif

    auto *attn_mask_tensor = wrapper->interpreter->getSessionInput(
        wrapper->session, "attention_mask");
    auto *token_type_tensor = wrapper->interpreter->getSessionInput(
        wrapper->session, "token_type_ids");

    if (wrapper->last_seq_len != MAX_SEQ) {
      wrapper->interpreter->resizeTensor(input_ids_tensor, shape);
      if (attn_mask_tensor) {
        wrapper->interpreter->resizeTensor(attn_mask_tensor, shape);
      }
      if (token_type_tensor) {
        wrapper->interpreter->resizeTensor(token_type_tensor, shape);
      }
      wrapper->interpreter->resizeSession(wrapper->session);
      wrapper->last_seq_len = MAX_SEQ;

      // Also release cached host buffers when dimensionality changes
      wrapper->host_input_ids.reset(
          new MNN::Tensor(input_ids_tensor, MNN::Tensor::CAFFE));

      if (attn_mask_tensor) {
        wrapper->host_attention_mask.reset(
            new MNN::Tensor(attn_mask_tensor, MNN::Tensor::CAFFE));
      } else {
        wrapper->host_attention_mask.reset(nullptr);
      }

      if (token_type_tensor) {
        wrapper->host_token_type_ids.reset(
            new MNN::Tensor(token_type_tensor, MNN::Tensor::CAFFE));
      } else {
        wrapper->host_token_type_ids.reset(nullptr);
      }

      // Output tensor size might be unknown until after inference, but we can
      // reset the old buffer anyway
      wrapper->host_output.reset(nullptr);
    }

    // 3. Copy input data using reused buffers
    // input_ids
    {
      if (!wrapper->host_input_ids) {
    wrapper->host_input_ids.reset(
        new MNN::Tensor(input_ids_tensor, MNN::Tensor::CAFFE));
  }
  // No need to zero out again if we already did in resizeSession block?
  // Actually, we must zero out because previous call might have had longer sequence
  auto *dst = wrapper->host_input_ids->host<int>();
  std::memset(dst, 0, MAX_SEQ * sizeof(int));
  memcpy(dst, token_ids.data(), std::min(seq_len, MAX_SEQ) * sizeof(int));
  input_ids_tensor->copyFromHostTensor(wrapper->host_input_ids.get());
}
// attention_mask
if (attn_mask_tensor) {
  if (!wrapper->host_attention_mask) {
    wrapper->host_attention_mask.reset(
        new MNN::Tensor(attn_mask_tensor, MNN::Tensor::CAFFE));
  }
  auto *dst = wrapper->host_attention_mask->host<int>();
  std::memset(dst, 0, MAX_SEQ * sizeof(int));
  memcpy(dst, attention_mask.data(), std::min(seq_len, MAX_SEQ) * sizeof(int));
  attn_mask_tensor->copyFromHostTensor(wrapper->host_attention_mask.get());
}
// token_type_ids
if (token_type_tensor) {
  if (!wrapper->host_token_type_ids) {
    wrapper->host_token_type_ids.reset(
        new MNN::Tensor(token_type_tensor, MNN::Tensor::CAFFE));
  }
  auto *dst = wrapper->host_token_type_ids->host<int>();
  std::memset(dst, 0, MAX_SEQ * sizeof(int));
  memcpy(dst, token_type_ids.data(), std::min(seq_len, MAX_SEQ) * sizeof(int));
  token_type_tensor->copyFromHostTensor(wrapper->host_token_type_ids.get());
}

    // 4. Run inference
#ifdef DEBUG_EMBEDDING
    LOGI("embedding_generate: running inference...");
#endif
    wrapper->interpreter->runSession(wrapper->session);
#ifdef DEBUG_EMBEDDING
    LOGI("embedding_generate: inference complete, reading output...");
#endif

    // 5. Get output (use cached or search iteratively)
    MNN::Tensor *out_tensor = nullptr;
    const char *output_names[] = {"last_hidden_state", "embeddings",
                                  "sentence_embedding", "output", nullptr};
    for (int i = 0; output_names[i]; i++) {
      out_tensor = wrapper->interpreter->getSessionOutput(wrapper->session,
                                                          output_names[i]);
      if (out_tensor)
        break;
    }
    if (!out_tensor) {
      out_tensor =
          wrapper->interpreter->getSessionOutput(wrapper->session, nullptr);
    }
    if (!out_tensor) {
      LOGE("No output tensor found after inference");
      return 0;
    }

    // Copy output to host memory
    if (!wrapper->host_output ||
        wrapper->host_output->size() != out_tensor->size()) {
      wrapper->host_output.reset(
          new MNN::Tensor(out_tensor, MNN::Tensor::CAFFE));
    }
    out_tensor->copyToHostTensor(wrapper->host_output.get());

    auto out_shape = wrapper->host_output->shape();
    int dim = wrapper->embedding_dim;

    // 6. Pooling: CLS (first token) for BGE, or already pooled
    // Use thread_local to avoid repeated allocation during heavy batch
    // insertion
    thread_local std::vector<float> embedding_buf;
    if (embedding_buf.size() != dim) {
      embedding_buf.assign(dim, 0.0f);
    } else {
      std::fill(embedding_buf.begin(), embedding_buf.end(), 0.0f);
    }
    auto *data = wrapper->host_output->host<float>();

    if (out_shape.size() == 3) {
      // [batch=1, seq_len, dim] -> CLS pooling (take index 0)
      memcpy(embedding_buf.data(), data, dim * sizeof(float));
    } else if (out_shape.size() == 2) {
      // [batch=1, dim] -> already pooled
      memcpy(embedding_buf.data(), data, dim * sizeof(float));
    } else if (out_shape.size() == 1) {
      // [dim] -> single embedding
      int copy_dim = std::min(dim, (int)out_shape[0]);
      memcpy(embedding_buf.data(), data, copy_dim * sizeof(float));
    }

    // 7. L2 Normalize (Vectorized with ARM NEON if available)
    float norm = 0.0f;
    float *emb_ptr = embedding_buf.data();

#if defined(__ARM_NEON)
    int i = 0;
    float32x4_t sum_vec = vdupq_n_f32(0.0f);
    for (; i <= dim - 4; i += 4) {
      float32x4_t v = vld1q_f32(emb_ptr + i);
      sum_vec = vmlaq_f32(sum_vec, v, v);
    }
    float sum_arr[4];
    vst1q_f32(sum_arr, sum_vec);
    norm = sum_arr[0] + sum_arr[1] + sum_arr[2] + sum_arr[3];
    // Remaining elements
    for (; i < dim; ++i) {
      norm += emb_ptr[i] * emb_ptr[i];
    }
#else
    for (int i = 0; i < dim; i++) {
      norm += emb_ptr[i] * emb_ptr[i];
    }
#endif

    norm = std::sqrt(norm);
    if (norm > 1e-6f) {
#if defined(__ARM_NEON)
      int j = 0;
      float32x4_t inv_norm_vec = vdupq_n_f32(1.0f / norm);
      for (; j <= dim - 4; j += 4) {
        float32x4_t v = vld1q_f32(emb_ptr + j);
        v = vmulq_f32(v, inv_norm_vec);
        vst1q_f32(emb_ptr + j, v);
      }
      for (; j < dim; ++j) {
        emb_ptr[j] /= norm;
      }
#else
      for (int i = 0; i < dim; i++) {
        emb_ptr[i] /= norm;
      }
#endif
    }

    // 8. Copy to output
    size_t copy_size = std::min((size_t)dim, output_size);
    std::memcpy(output, embedding_buf.data(), copy_size * sizeof(float));
    if (mnnr_timing_enabled()) {
      auto t1 = std::chrono::steady_clock::now();
      auto total_ms =
          std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
      LOGI("timing embedding_generate total_ms=%lld text_len=%zu dim=%d",
           (long long)total_ms, text ? std::strlen(text) : 0, dim);
    }
    return copy_size;
  } catch (const std::exception &e) {
    LOGE("mnnr_embedding_generate exception: %s", e.what());
    return 0;
  } catch (...) {
    LOGE("mnnr_embedding_generate unknown exception");
    return 0;
  }
}

int32_t mnnr_embedding_dim(MNNR_Embedding embedding) {
  if (!embedding)
    return 0;
  auto *wrapper = static_cast<MNNREmbedding *>(embedding);
  return wrapper->embedding_dim;
}
MNNR_LLM mnnr_llm_create(const char *config_path, int32_t *error_code) {
  LOGI("mnnr_llm_create entry: config_path=%s",
       config_path ? config_path : "NULL");
  if (!config_path) {
    if (error_code)
      *error_code = MNNR_ERROR_INVALID_PARAM;
    return nullptr;
  }

  try {
    LOGI("Calling Llm::createLLM...");
    auto *wrapper = new MNNRLlm();
    wrapper->llm = MNN::Transformer::Llm::createLLM(config_path);
    LOGI("Llm::createLLM returned %p", wrapper->llm);

    if (!wrapper->llm) {
      if (error_code)
        *error_code = MNNR_ERROR_MODEL_LOAD_FAILED;
      delete wrapper;
      return nullptr;
    }

    if (error_code)
      *error_code = MNNR_SUCCESS;
    return wrapper;
  } catch (const std::exception &e) {
    LOGE("mnnr_llm_create exception: %s", e.what());
    if (error_code)
      *error_code = MNNR_ERROR_RUNTIME;
    return nullptr;
  }
}

uint32_t mnnr_llm_load(MNNR_LLM llm) {
  LOGI("mnnr_llm_load entry: llm=%p", llm);
  if (!llm)
    return MNNR_ERROR_INVALID_PARAM;

  auto *wrapper = static_cast<MNNRLlm *>(llm);
  if (!wrapper->llm)
    return MNNR_ERROR_NULL_POINTER;

  try {
    if (!wrapper->llm->load()) {
      LOGE("wrapper->llm->load() returned false");
      return MNNR_ERROR_MODEL_LOAD_FAILED;
    }
    LOGI("mnnr_llm_load success");
    return MNNR_SUCCESS;
  } catch (const std::exception &e) {
    LOGE("mnnr_llm_load exception: %s", e.what());
    return MNNR_ERROR_RUNTIME;
  }
}

void mnnr_llm_destroy(MNNR_LLM llm) {
  if (llm) {
    delete static_cast<MNNRLlm *>(llm);
  }
}

size_t mnnr_llm_generate(MNNR_LLM llm, const char *prompt, char *output,
                         size_t output_size, int32_t max_tokens) {
  if (!llm || !prompt || !output || output_size == 0) {
    return 0;
  }

  auto *wrapper = static_cast<MNNRLlm *>(llm);
  if (!wrapper->llm)
    return 0;

  try {
    std::ostringstream oss;
    std::string query(prompt);
    wrapper->llm->response(query, &oss, "");
    wrapper->last_response = oss.str();

    size_t copy_size = std::min(wrapper->last_response.size(), output_size - 1);
    std::memcpy(output, wrapper->last_response.c_str(), copy_size);
    output[copy_size] = '\0';

    return copy_size;
  } catch (const std::exception &e) {
    output[0] = '\0';
    return 0;
  }
}

class CallbackStreambuf : public std::streambuf {
public:
  CallbackStreambuf(MNNR_TokenCallback callback, void *user_data,
                    std::atomic<bool> *cancelled)
      : callback_(callback), user_data_(user_data), cancelled_(cancelled) {}

protected:
  int overflow(int c) override {
    if (cancelled_ && *cancelled_) {
      throw std::runtime_error("MNNR_CANCELLED");
    }

    if (c != EOF) {
      std::lock_guard<std::recursive_mutex> lock(mutex_);

      // Safety: Prevent infinite buffer growth
      if (buffer_.length() > 64 * 1024) {
        buffer_.clear();
      }

      unsigned char ch = static_cast<unsigned char>(c);
      buffer_ += static_cast<char>(ch);

      // UTF-8 lead byte detection
      bool is_continuation = (ch & 0xC0) == 0x80;
      bool is_ascii = (ch & 0x80) == 0x00;

      // Better safe streaming parser flush boundary
      if (!is_continuation && !is_ascii) {
        if ((ch & 0xE0) == 0xC0)
          utf8_remaining_ = 1;
        else if ((ch & 0xF0) == 0xE0)
          utf8_remaining_ = 2;
        else if ((ch & 0xF8) == 0xF0)
          utf8_remaining_ = 3;
        else
          utf8_remaining_ = 0;
      } else if (is_continuation && utf8_remaining_ > 0) {
        utf8_remaining_--;
      } else if (is_continuation) {
        // Fallback: If we get a continuation byte when we don't expect one,
        // it's likely a stream breaking mid-byte or a bug. Reset to be safe.
        // Also flush on whitespace/punctuation to avoid sticking.
        utf8_remaining_ = 0;
      } else {
        utf8_remaining_ = 0;
      }

      bool flush_boundary = false;
      if (utf8_remaining_ == 0) {
        flush_boundary = std::isspace(ch) || std::ispunct(ch) ||
                         buffer_.size() >= kFlushChunkChars;
      }

      if (flush_boundary && callback_ && !buffer_.empty()) {
        callback_(buffer_.c_str(), user_data_);
        buffer_.clear();
      }
    }
    return c;
  }

  int sync() override {
    if (cancelled_ && *cancelled_) {
      throw std::runtime_error("MNNR_CANCELLED");
    }
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    if (callback_ && !buffer_.empty() && utf8_remaining_ == 0) {
      callback_(buffer_.c_str(), user_data_);
      buffer_.clear();
    }
    return 0;
  }

private:
  static constexpr size_t kFlushChunkChars = 32;
  MNNR_TokenCallback callback_;
  void *user_data_;
  std::string buffer_;
  int utf8_remaining_ = 0;
  std::recursive_mutex mutex_;
  std::atomic<bool> *cancelled_;
};

uint32_t mnnr_llm_generate_stream(MNNR_LLM llm, const char *prompt,
                                  MNNR_TokenCallback callback, void *user_data,
                                  int32_t max_tokens) {
  LOGI("mnnr_llm_generate_stream entry: prompt_len=%zu",
       prompt ? std::strlen(prompt) : 0);
  if (!llm || !prompt || !callback) {
    return MNNR_ERROR_INVALID_PARAM;
  }

  auto *wrapper = static_cast<MNNRLlm *>(llm);
  std::lock_guard<std::mutex> lock(wrapper->mutex);
  if (!wrapper->llm)
    return MNNR_ERROR_NULL_POINTER;

  wrapper->cancelled = false;
  auto t0 = std::chrono::steady_clock::now();

  try {
    CallbackStreambuf streambuf(callback, user_data, &wrapper->cancelled);
    std::ostream os(&streambuf);
    std::string query(prompt);
    wrapper->llm->response(query, &os, "");
    os.flush();
    if (mnnr_timing_enabled()) {
      auto t1 = std::chrono::steady_clock::now();
      auto total_ms =
          std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
      LOGI("timing llm_generate_stream total_ms=%lld prompt_len=%zu",
           (long long)total_ms, std::strlen(prompt));
    }
    return MNNR_SUCCESS;
  } catch (const std::exception &e) {
    if (std::string(e.what()) == "MNNR_CANCELLED") {
      LOGI("mnnr_llm_generate_stream: cancelled by user");
      return MNNR_SUCCESS;
    }
    LOGE("mnnr_llm_generate_stream exception: %s", e.what());
    return MNNR_ERROR_RUNTIME;
  }
}

void mnnr_llm_cancel(MNNR_LLM llm) {
  if (!llm)
    return;
  auto *wrapper = static_cast<MNNRLlm *>(llm);
  wrapper->cancelled = true;
}

void mnnr_llm_reset(MNNR_LLM llm) {
  if (!llm)
    return;
  auto *wrapper = static_cast<MNNRLlm *>(llm);
  std::lock_guard<std::mutex> lock(wrapper->mutex);
  if (wrapper->llm)
    wrapper->llm->reset();
}

void mnnr_llm_set_config(MNNR_LLM llm, const char *config_json) {
  if (!llm || !config_json)
    return;
  auto *wrapper = static_cast<MNNRLlm *>(llm);
  std::lock_guard<std::mutex> lock(wrapper->mutex);
  if (wrapper->llm)
    wrapper->llm->set_config(std::string(config_json));
}

int32_t mnnr_llm_stopped(MNNR_LLM llm) {
  if (!llm)
    return 1;
  auto *wrapper = static_cast<MNNRLlm *>(llm);
  std::lock_guard<std::mutex> lock(wrapper->mutex);
  if (!wrapper->llm)
    return 1;
  return wrapper->llm->stoped() ? 1 : 0;
}

void mnnr_llm_get_stats(MNNR_LLM llm, int32_t *prompt_tokens,
                        int32_t *gen_tokens, int64_t *prefill_us,
                        int64_t *decode_us) {
  if (prompt_tokens)
    *prompt_tokens = 0;
  if (gen_tokens)
    *gen_tokens = 0;
  if (prefill_us)
    *prefill_us = 0;
  if (decode_us)
    *decode_us = 0;
}

size_t mnnr_get_memory_usage_llm(MNNR_LLM llm) { return 0; }

#else // HAS_MNN_LLM not defined - provide LLM & Embedding stubs

extern "C" {

MNNR_LLM mnnr_llm_create(const char *config_path, int32_t *error_code) {
  if (error_code)
    *error_code = MNNR_ERROR_UNSUPPORTED;
  return nullptr;
}

uint32_t mnnr_llm_load(MNNR_LLM llm) { return MNNR_ERROR_UNSUPPORTED; }

void mnnr_llm_destroy(MNNR_LLM llm) {}

size_t mnnr_llm_generate(MNNR_LLM llm, const char *prompt, char *output,
                         size_t output_size, int32_t max_tokens) {
  return 0;
}

uint32_t mnnr_llm_generate_stream(MNNR_LLM llm, const char *prompt,
                                  MNNR_TokenCallback callback, void *user_data,
                                  int32_t max_tokens) {
  return MNNR_ERROR_UNSUPPORTED;
}

void mnnr_llm_reset(MNNR_LLM llm) {}

void mnnr_llm_set_config(MNNR_LLM llm, const char *config_json) {}

int32_t mnnr_llm_stopped(MNNR_LLM llm) { return 1; }

void mnnr_llm_get_stats(MNNR_LLM llm, int32_t *prompt_tokens,
                        int32_t *gen_tokens, int64_t *prefill_us,
                        int64_t *decode_us) {}

size_t mnnr_get_memory_usage_llm(MNNR_LLM llm) { return 0; }

MNNR_Embedding mnnr_embedding_create(const char *config_path,
                                     int32_t *error_code) {
  if (error_code)
    *error_code = MNNR_ERROR_UNSUPPORTED;
  return nullptr;
}

uint32_t mnnr_embedding_load(MNNR_Embedding embedding) {
  return MNNR_ERROR_UNSUPPORTED;
}

void mnnr_embedding_destroy(MNNR_Embedding embedding) {}

size_t mnnr_embedding_generate(MNNR_Embedding embedding, const char *text,
                               float *output, size_t output_size) {
  return 0;
}

int32_t mnnr_embedding_dim(MNNR_Embedding embedding) { return 0; }

} // extern "C"

#endif // HAS_MNN_LLM

} // extern "C"

#else // MNN_AVAILABLE not defined - provide all stubs

extern "C" {

// =============================================================================
// Stub Implementation (when MNN is not available)
// =============================================================================

const char *mnnr_get_version(void) { return "stub-3.2.0"; }

int mnnr_is_available(void) { return 0; }

MNNR_Engine mnnr_create_engine(const char *model_path,
                               const MNNR_Config *config, int32_t *error_code) {
  if (error_code)
    *error_code = MNNR_ERROR_UNSUPPORTED;
  return nullptr;
}

MNNR_Engine mnnr_create_engine_from_buffer(const void *buffer,
                                           size_t buffer_size,
                                           const MNNR_Config *config,
                                           int32_t *error_code) {
  if (error_code)
    *error_code = MNNR_ERROR_UNSUPPORTED;
  return nullptr;
}

void mnnr_destroy_engine(MNNR_Engine engine) {}

uint32_t mnnr_run_inference(MNNR_Engine engine, const float *input,
                            size_t input_size, float *output,
                            size_t output_size) {
  return MNNR_ERROR_UNSUPPORTED;
}

void *mnnr_get_session_input(MNNR_Engine engine, const char *name) {
  return nullptr;
}

uint32_t mnnr_get_session_input_info(MNNR_Engine engine, const char *name,
                                     int32_t *shape, int32_t *ndim) {
  return MNNR_ERROR_UNSUPPORTED;
}

uint32_t mnnr_resize_session_input(MNNR_Engine engine, const char *name,
                                   const int32_t *shape, int32_t ndim) {
  return MNNR_ERROR_UNSUPPORTED;
}

void *mnnr_get_session_output(MNNR_Engine engine, const char *name) {
  return nullptr;
}

uint32_t mnnr_get_session_output_info(MNNR_Engine engine, const char *name,
                                      int32_t *shape, int32_t *ndim) {
  return MNNR_ERROR_UNSUPPORTED;
}

uint32_t mnnr_get_input_shape(MNNR_Engine engine, int32_t index, int32_t *shape,
                              int32_t *ndim) {
  return MNNR_ERROR_UNSUPPORTED;
}

uint32_t mnnr_get_output_shape(MNNR_Engine engine, int32_t index,
                               int32_t *shape, int32_t *ndim) {
  return MNNR_ERROR_UNSUPPORTED;
}

uint32_t mnnr_resize_input(MNNR_Engine engine, int32_t index,
                           const int32_t *shape, int32_t ndim) {
  return MNNR_ERROR_UNSUPPORTED;
}

MNNR_SessionPool mnnr_create_session_pool(const char *model_path,
                                          const MNNR_Config *config,
                                          int32_t pool_size) {
  return nullptr;
}

void mnnr_destroy_session_pool(MNNR_SessionPool pool) {}

uint32_t mnnr_pool_run_inference(MNNR_SessionPool pool, const float *input,
                                 size_t input_size, float *output,
                                 size_t output_size) {
  return MNNR_ERROR_UNSUPPORTED;
}

int32_t mnnr_pool_available_sessions(MNNR_SessionPool pool) { return 0; }

size_t mnnr_get_memory_usage(MNNR_Engine engine) { return 0; }

void mnnr_release_cache(MNNR_Engine engine) {}

void mnnr_set_global_executor_config(int32_t num_threads, int32_t backend) {}

uint32_t mnnr_llm_prefill(MNNR_Engine engine, const int32_t *token_ids,
                          size_t num_tokens, float *logits, size_t vocab_size) {
  return MNNR_ERROR_UNSUPPORTED;
}

uint32_t mnnr_llm_decode(MNNR_Engine engine, int32_t token_id, float *logits,
                         size_t vocab_size) {
  return MNNR_ERROR_UNSUPPORTED;
}

void mnnr_llm_clear_cache(MNNR_Engine engine) {}

size_t mnnr_llm_cache_length(MNNR_Engine engine) { return 0; }

MNNR_LLM mnnr_llm_create(const char *config_path, int32_t *error_code) {
  if (error_code)
    *error_code = MNNR_ERROR_UNSUPPORTED;
  return nullptr;
}

uint32_t mnnr_llm_load(MNNR_LLM llm) { return MNNR_ERROR_UNSUPPORTED; }

void mnnr_llm_destroy(MNNR_LLM llm) {}

size_t mnnr_llm_generate(MNNR_LLM llm, const char *prompt, char *output,
                         size_t output_size, int32_t max_tokens) {
  return 0;
}

uint32_t mnnr_llm_generate_stream(MNNR_LLM llm, const char *prompt,
                                  MNNR_TokenCallback callback, void *user_data,
                                  int32_t max_tokens) {
  return MNNR_ERROR_UNSUPPORTED;
}

void mnnr_llm_reset(MNNR_LLM llm) {}

void mnnr_llm_cancel(MNNR_LLM llm) {}

void mnnr_llm_set_config(MNNR_LLM llm, const char *config_json) {}

int32_t mnnr_llm_stopped(MNNR_LLM llm) { return 1; }

void mnnr_llm_get_stats(MNNR_LLM llm, int32_t *prompt_tokens,
                        int32_t *gen_tokens, int64_t *prefill_us,
                        int64_t *decode_us) {}

size_t mnnr_get_memory_usage_llm(MNNR_LLM llm) { return 0; }

MNNR_Embedding mnnr_embedding_create(const char *config_path,
                                     int32_t *error_code) {
  if (error_code)
    *error_code = MNNR_ERROR_UNSUPPORTED;
  return nullptr;
}

uint32_t mnnr_embedding_load(MNNR_Embedding embedding) {
  return MNNR_ERROR_UNSUPPORTED;
}

void mnnr_embedding_destroy(MNNR_Embedding embedding) {}

size_t mnnr_embedding_generate(MNNR_Embedding embedding, const char *text,
                               float *output, size_t output_size) {
  return 0;
}

int32_t mnnr_embedding_dim(MNNR_Embedding embedding) { return 0; }

} // extern "C"

#endif // MNN_AVAILABLE
