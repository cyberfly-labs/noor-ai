#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <ftw.h>
#include <future>
#include <mutex>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "../include/edgemind_core.h"
#include "../include/mnn_wrapper.h"
#include "zvec_c.h"
#include "asr_recognizer.h"

#include "rapidjson/document.h"
#include "rapidjson/stringbuffer.h"
#include "rapidjson/writer.h"

#ifdef SUPERTONIC_AVAILABLE
#include "supertonic/supertonic_tts.h"
#endif

#include <cstdio>

#if defined(ANDROID)
#include <android/log.h>
#endif
#ifndef TAG
#define TAG "EdgeMindCore"
#endif

#if defined(ANDROID)
#ifndef ANDROID_LOG_INFO
#define ANDROID_LOG_INFO 4
#endif
#ifndef ANDROID_LOG_WARN
#define ANDROID_LOG_WARN 5
#endif
#ifndef ANDROID_LOG_ERROR
#define ANDROID_LOG_ERROR 6
#endif
#ifndef LOGI
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#endif
#ifndef LOGW
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#endif
#ifndef LOGE
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#endif
#else
#ifndef LOGI
#define LOGI(...)                                                             \
  do {                                                                        \
    std::fprintf(stderr, "[INFO] %s: ", TAG);                                \
    std::fprintf(stderr, __VA_ARGS__);                                        \
    std::fprintf(stderr, "\n");                                             \
  } while (0)
#endif
#ifndef LOGW
#define LOGW(...)                                                             \
  do {                                                                        \
    std::fprintf(stderr, "[WARN] %s: ", TAG);                                \
    std::fprintf(stderr, __VA_ARGS__);                                        \
    std::fprintf(stderr, "\n");                                             \
  } while (0)
#endif
#ifndef LOGE
#define LOGE(...)                                                             \
  do {                                                                        \
    std::fprintf(stderr, "[ERROR] %s: ", TAG);                               \
    std::fprintf(stderr, __VA_ARGS__);                                        \
    std::fprintf(stderr, "\n");                                             \
  } while (0)
#endif
#endif

// =============================================================================
// Global State
// =============================================================================

struct GlobalState {
  mutable std::recursive_mutex lifecycle_mutex;
  mutable std::recursive_mutex cache_mutex;
  mutable std::recursive_mutex sources_mutex;

  std::atomic<bool> initialized{false};
  MNNR_LLM llm = nullptr;
  MNNR_Embedding embedding_engine = nullptr;
  ZvecCollection collection = nullptr;
  std::string collection_path;
  std::string model_dir;
  std::string embedding_path;
  std::string config_json;
  std::string active_session_id;
  int32_t cached_embedding_dim = 0;
  bool engines_loaded = false;
  std::unordered_set<std::string> deleted_hashes;
  // Embedding cache for repeated queries
  std::unordered_map<std::string, std::vector<float>> embedding_cache;
  // ASR
  std::string whisper_dir;
  std::unique_ptr<edgemind::AsrRecognizer> asr_recognizer;
  bool asr_rnnoise_enabled = false;
  // TTS (supertonic-mnn)
  std::string tts_dir;
  std::string tts_voice = "F1";
  float tts_gain = 1.0f;
#ifdef SUPERTONIC_AVAILABLE
  SupertonicTTS *tts_engine = nullptr;
#endif
};

static std::atomic<bool> g_chat_active{false};

static GlobalState g_state;

// ---------------------------------------------------------------------------
// Guarded Dart stream callback
// ---------------------------------------------------------------------------
// Native detached threads must never call a Dart NativeCallable trampoline
// after it has been freed (e.g. during Flutter hot restart).  We store the
// Dart callback pointer behind a mutex so it can be atomically checked and
// invoked.  Dart registers/unregisters via edgemind_register_dart_callbacks /
// edgemind_unregister_dart_callbacks.
// ---------------------------------------------------------------------------
static std::recursive_mutex g_dart_cb_mutex;
static StreamCallback g_dart_llm_cb = nullptr;
static StreamCallback g_dart_asr_cb = nullptr;

// Safe wrapper: locks the mutex, checks if the callback is still registered,
// and only then forwards to Dart.  If the callback is gone, allocated strings
// are freed so we don't leak memory.
static void guarded_llm_callback(const char *token, int32_t is_final,
                                 void *user_data) {
  std::lock_guard<std::recursive_mutex> lock(g_dart_cb_mutex);
  if (g_dart_llm_cb) {
    g_dart_llm_cb(token, is_final, user_data);
  } else if (token) {
    free(const_cast<char *>(token));
  }
}

static void guarded_asr_callback(const char *token, int32_t is_final,
                                 void *user_data) {
  std::lock_guard<std::recursive_mutex> lock(g_dart_cb_mutex);
  if (g_dart_asr_cb) {
    g_dart_asr_cb(token, is_final, user_data);
  } else if (token) {
    free(const_cast<char *>(token));
  }
}

static bool edgemind_timing_enabled() {
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

// --- Deleted-hashes file helpers ---
static std::string deleted_hashes_path() {
  return g_state.collection_path + "_deleted.txt";
}

static void load_deleted_hashes() {
  std::lock_guard<std::recursive_mutex> lock(g_state.sources_mutex);
  g_state.deleted_hashes.clear();
  std::ifstream f(deleted_hashes_path());
  if (!f.is_open())
    return;
  std::string line;
  while (std::getline(f, line)) {
    if (!line.empty())
      g_state.deleted_hashes.insert(line);
  }
}

static void save_deleted_hashes() {
  std::lock_guard<std::recursive_mutex> lock(g_state.sources_mutex);
  std::ofstream f(deleted_hashes_path(), std::ios::trunc);
  if (!f.is_open())
    return;
  for (auto &h : g_state.deleted_hashes) {
    f << h << "\n";
  }
}

static std::string sources_index_path() {
  return g_state.collection_path + "_sources.tsv";
}

static bool
load_sources_index(std::unordered_map<std::string, std::string> &entries) {
  entries.clear();
  std::ifstream f(sources_index_path());
  if (!f.is_open()) {
    return false;
  }
  std::string line;
  while (std::getline(f, line)) {
    if (line.empty()) {
      continue;
    }
    size_t pos = line.find('\t');
    if (pos == std::string::npos || pos == 0 || pos + 1 >= line.size()) {
      continue;
    }
    std::string hash = line.substr(0, pos);
    std::string metadata = line.substr(pos + 1);
    entries[hash] = metadata;
  }
  return true;
}

static void save_sources_index(
    const std::unordered_map<std::string, std::string> &entries) {
  static std::string last_saved_content;
  std::string current_content;
  for (const auto &kv : entries) {
    current_content += kv.first + "\t" + kv.second + "\n";
  }
  if (current_content == last_saved_content) {
    return;
  }
  std::ofstream f(sources_index_path(), std::ios::trunc);
  if (!f.is_open()) {
    return;
  }
  f << current_content;
  last_saved_content = std::move(current_content);
}

static void upsert_source_index(const std::string &hash,
                                const std::string &metadata) {
  std::lock_guard<std::recursive_mutex> lock(g_state.sources_mutex);
  if (hash.empty()) {
    return;
  }
  std::unordered_map<std::string, std::string> entries;
  load_sources_index(entries);
  entries[hash] = metadata;
  save_sources_index(entries);
}

static void remove_source_index(const std::string &hash) {
  std::lock_guard<std::recursive_mutex> lock(g_state.sources_mutex);
  if (hash.empty()) {
    return;
  }
  std::unordered_map<std::string, std::string> entries;
  if (!load_sources_index(entries)) {
    return;
  }
  entries.erase(hash);
  save_sources_index(entries);
}

static void clear_source_index() {
  std::lock_guard<std::recursive_mutex> lock(g_state.sources_mutex);
  std::remove(sources_index_path().c_str());
}

// --- Helper Functions ---
// Helper to allocate strings for Dart to take ownership and eventually free.
// Uses memcpy instead of strcpy for explicit bounds safety (buffer is sized
// exactly once and length is captured atomically with the copy).
static const char *allocate_string(const std::string &str) {
  const size_t len = str.size();
  char *cstr = static_cast<char *>(std::malloc(len + 1));
  if (cstr) {
    std::memcpy(cstr, str.data(), len);
    cstr[len] = '\0';
  }
  return cstr;
}

static std::string get_json_string_value(const std::string &json,
                                         const std::string &key) {
  rapidjson::Document doc;
  if (!doc.Parse(json.c_str()).HasParseError()) {
    if (doc.HasMember(key.c_str()) && doc[key.c_str()].IsString()) {
      return doc[key.c_str()].GetString();
    }
  }
  return "";
}

static std::string ensure_metadata_hash(const std::string &metadata_json,
                                        const std::string &hash) {
  rapidjson::Document doc;
  if (doc.Parse(metadata_json.c_str()).HasParseError() || !doc.IsObject()) {
    doc.SetObject();
  }
  auto &allocator = doc.GetAllocator();
  rapidjson::Value hash_key("hash", allocator);
  rapidjson::Value hash_val(hash.c_str(), allocator);
  if (doc.HasMember("hash")) {
    doc["hash"] = hash_val;
  } else {
    doc.AddMember(hash_key, hash_val, allocator);
  }
  rapidjson::StringBuffer buffer;
  rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
  doc.Accept(writer);
  return buffer.GetString();
}

static std::string json_value_to_string(const rapidjson::Value &value) {
  rapidjson::StringBuffer buffer;
  rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
  value.Accept(writer);
  return buffer.GetString();
}

static std::string sanitize_doc_id_component(const std::string &input) {
  std::string output;
  output.reserve(input.size());

  bool last_was_underscore = false;
  for (unsigned char c : input) {
    const bool allowed = std::isalnum(c) || c == '_' || c == '-';
    const char out = allowed ? static_cast<char>(c) : '_';
    if (out == '_') {
      if (!last_was_underscore) {
        output.push_back(out);
      }
      last_was_underscore = true;
    } else {
      output.push_back(out);
      last_was_underscore = false;
    }
  }

  while (!output.empty() && output.front() == '_') {
    output.erase(output.begin());
  }
  while (!output.empty() && output.back() == '_') {
    output.pop_back();
  }

  if (output.empty()) {
    return "doc";
  }
  return output;
}

static std::string chunk_id_prefix_for_hash(const std::string &hash) {
  return "chunk_" + sanitize_doc_id_component(hash) + "_";
}

static std::string chunk_id_for_hash(const std::string &hash, int index) {
  return chunk_id_prefix_for_hash(hash) + std::to_string(index);
}

// Helper to safely escape strings for JSON injection
static std::string escape_json_string(const std::string &input) {
  std::string output;
  output.reserve(input.length() * 1.2);
  for (char c : input) {
    if (c == '"')
      output += "\\\"";
    else if (c == '\\')
      output += "\\\\";
    else if (c == '\b')
      output += "\\b";
    else if (c == '\f')
      output += "\\f";
    else if (c == '\n')
      output += "\\n";
    else if (c == '\r')
      output += "\\r";
    else if (c == '\t')
      output += "\\t";
    else if (c >= 0 && c <= 0x1f) {
      char buf[8];
      snprintf(buf, sizeof(buf), "\\u%04x", c);
      output += buf;
    } else
      output += c;
  }
  return output;
}

static bool ends_with(const std::string &value, const std::string &suffix) {
  if (suffix.size() > value.size()) {
    return false;
  }
  return value.compare(value.size() - suffix.size(), suffix.size(), suffix) ==
         0;
}

static std::string join_path(const std::string &base, const std::string &name) {
  if (base.empty()) {
    return name;
  }
  if (base.back() == '/') {
    return base + name;
  }
  return base + "/" + name;
}

static std::string escape_filter_literal(const std::string &input) {
  std::string output;
  output.reserve(input.size());
  for (char c : input) {
    if (c == '\\' || c == '\'') {
      output.push_back('\\');
    }
    output.push_back(c);
  }
  return output;
}

// BGE-Small-EN-v1.5 query instruction prefix for better retrieval recall.
// Passages are embedded without prefix (per BAAI recommendation).
static const char *BGE_QUERY_PREFIX =
    "Represent this sentence for searching relevant passages: ";

static constexpr size_t MAX_QUERY_CHARS = 1024; // Truncate ultra-long queries

static std::string prepare_query_for_embedding(const std::string &query) {
  std::string trimmed = query.substr(0, MAX_QUERY_CHARS);
  return std::string(BGE_QUERY_PREFIX) + trimmed;
}

static int32_t resolve_embedding_dim() {
  int32_t dim = g_state.cached_embedding_dim;
  if (g_state.embedding_engine) {
    int32_t runtime_dim = mnnr_embedding_dim(g_state.embedding_engine);
    if (runtime_dim > 0) {
      dim = runtime_dim;
    }
  }
  if (dim <= 0) {
    dim = 384;
  }
  return dim;
}

static bool directory_exists(const std::string &path) {
  struct stat info;
  if (stat(path.c_str(), &info) != 0) {
    return false;
  }
  return (info.st_mode & S_IFDIR) != 0;
}

static bool ensure_embedding_engine_loaded_locked(
    const std::string *override_path = nullptr) {
  if (override_path && !override_path->empty() &&
      g_state.embedding_path != *override_path) {
    if (g_state.embedding_engine) {
      mnnr_embedding_destroy(g_state.embedding_engine);
      g_state.embedding_engine = nullptr;
      g_state.cached_embedding_dim = 0;
      std::lock_guard<std::recursive_mutex> cache_lock(g_state.cache_mutex);
      g_state.embedding_cache.clear();
    }
    g_state.embedding_path = *override_path;
  }

  if (g_state.embedding_engine) {
    const int32_t dim = mnnr_embedding_dim(g_state.embedding_engine);
    if (dim > 0) {
      g_state.cached_embedding_dim = dim;
    }
    return true;
  }

  if (g_state.embedding_path.empty()) {
    LOGE("No embedding path configured");
    return false;
  }

  int32_t mnn_err = 0;
  LOGI("Creating embedding engine with path: %s",
       g_state.embedding_path.c_str());

  DIR *dir = opendir(g_state.embedding_path.c_str());
  std::string discovered_mnn;
  if (dir) {
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
      std::string fname(ent->d_name);
      if (fname.find(".mnn") != std::string::npos ||
          fname.find(".bin") != std::string::npos) {
        if (discovered_mnn.empty() || fname == "model.mnn" ||
            fname == "llm.mnn") {
          discovered_mnn = fname;
        }
      }
    }
    closedir(dir);
  }

  g_state.embedding_engine =
      mnnr_embedding_create(g_state.embedding_path.c_str(), &mnn_err);

  if (g_state.embedding_engine) {
    const uint32_t load_res = mnnr_embedding_load(g_state.embedding_engine);
    if (load_res != 0) {
      LOGE("Embedding load FAILED (res=%u).", load_res);
      mnnr_embedding_destroy(g_state.embedding_engine);
      g_state.embedding_engine = nullptr;

      if (!discovered_mnn.empty()) {
        std::string fallback = join_path(g_state.embedding_path, discovered_mnn);
        LOGI("Trying fallback path: %s", fallback.c_str());
        int fb_err = 0;
        g_state.embedding_engine =
            mnnr_embedding_create(fallback.c_str(), &fb_err);
        if (g_state.embedding_engine) {
          if (mnnr_embedding_load(g_state.embedding_engine) != 0) {
            mnnr_embedding_destroy(g_state.embedding_engine);
            g_state.embedding_engine = nullptr;
          }
        }
      }
    }
  }

  if (!g_state.embedding_engine) {
    LOGE("Failed to load embedding engine");
    return false;
  }

  g_state.cached_embedding_dim = mnnr_embedding_dim(g_state.embedding_engine);
  return true;
}

static int unlink_cb(const char *fpath, const struct stat *sb, int typeflag,
                     struct FTW *ftwbuf) {
  int rv = remove(fpath);
  if (rv)
    perror(fpath);
  return rv;
}

static void delete_directory(const std::string &path) {
  LOGI("Deleting directory: %s", path.c_str());
  nftw(path.c_str(), unlink_cb, 64, FTW_DEPTH | FTW_PHYS);
}

static const char *zvec_status_name(ZvecStatus status) {
  switch (status) {
  case ZVEC_OK:
    return "ZVEC_OK";
  case ZVEC_ERROR_INVALID_PARAM:
    return "ZVEC_ERROR_INVALID_PARAM";
  case ZVEC_ERROR_NOT_FOUND:
    return "ZVEC_ERROR_NOT_FOUND";
  case ZVEC_ERROR_IO:
    return "ZVEC_ERROR_IO";
  case ZVEC_ERROR_INTERNAL:
    return "ZVEC_ERROR_INTERNAL";
  case ZVEC_ERROR_ALREADY_EXISTS:
    return "ZVEC_ERROR_ALREADY_EXISTS";
  case ZVEC_ERROR_NOT_SUPPORTED:
    return "ZVEC_ERROR_NOT_SUPPORTED";
  }
  return "ZVEC_STATUS_UNKNOWN";
}

static std::string canonicalize_existing_path(const std::string &path) {
  if (path.empty()) {
    return path;
  }

  char actual_path[4096];
  if (realpath(path.c_str(), actual_path)) {
    return std::string(actual_path);
  }

  auto slash_pos = path.find_last_of('/');
  if (slash_pos == std::string::npos) {
    return path;
  }

  const std::string parent = path.substr(0, slash_pos);
  const std::string leaf = path.substr(slash_pos + 1);
  if (parent.empty() || leaf.empty()) {
    return path;
  }

  if (!realpath(parent.c_str(), actual_path)) {
    return path;
  }

  std::string resolved = actual_path;
  if (!resolved.empty() && resolved.back() != '/') {
    resolved += "/";
  }
  resolved += leaf;
  return resolved;
}

// Helper to open or recreate collection with schema validation
static ZvecStatus open_or_recreate_collection(const std::string &path,
                                              int32_t dim) {
  ZvecStatus z_status = ZVEC_ERROR_INTERNAL;
  if (directory_exists(path)) {
    LOGI("Checking existing collection at %s", path.c_str());
    LOGI("Bundled sidecars: sources=%s deleted=%s", sources_index_path().c_str(),
         deleted_hashes_path().c_str());
    z_status = zvec_open_collection(path.c_str(), &g_state.collection);
    if (z_status == ZVEC_OK) {
      uint32_t current_dim = zvec_get_dimension(g_state.collection);
      int has_hash = zvec_has_field(g_state.collection, "hash");
      LOGI("Collection status: dim=%u (expected %d), has_hash=%d", current_dim,
           dim, has_hash);

      if (current_dim != (uint32_t)dim || !has_hash) {
        LOGW("Schema mismatch! dim_match=%d, has_hash=%d. Recreating...",
             current_dim == (uint32_t)dim, has_hash);
        zvec_close_collection(g_state.collection);
        g_state.collection = nullptr;
        delete_directory(path);
        g_state.deleted_hashes.clear();
        save_deleted_hashes();
        clear_source_index();
        z_status = ZVEC_ERROR_NOT_FOUND;
      }
    } else {
      const char *last_error = zvec_get_last_error();
      LOGE("Failed to open existing collection: status=%d (%s), last_error=%s",
           z_status, zvec_status_name(z_status),
           last_error != nullptr ? last_error : "<none>");
      LOGW("Existing collection at %s is unreadable. Recreating from scratch.",
           path.c_str());
      delete_directory(path);
      g_state.deleted_hashes.clear();
      save_deleted_hashes();
      clear_source_index();
      z_status = ZVEC_ERROR_NOT_FOUND;
    }
  }

  if (z_status != ZVEC_OK) {
    LOGI("Creating fresh collection at %s with dim %d", path.c_str(), dim);
    z_status = zvec_create_collection(path.c_str(), "default", (uint32_t)dim,
                                      &g_state.collection);
    if (z_status != ZVEC_OK) {
      const char *last_error = zvec_get_last_error();
      LOGE("Failed to create fresh collection: status=%d (%s), last_error=%s",
           z_status, zvec_status_name(z_status),
           last_error != nullptr ? last_error : "<none>");
    }
    if (z_status == ZVEC_OK) {
      g_state.deleted_hashes.clear();
      save_deleted_hashes();
      clear_source_index();
    }
  }
  return z_status;
}

// Helper to ensure LLM and Embedding engines are loaded lazily
static bool ensure_engines_loaded() {
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);

  if (!g_state.initialized) {
    LOGE("ensure_engines_loaded: Core not initialized with config paths");
    return false;
  }

  if (g_state.engines_loaded)
    return true;

  LOGI("Lazy loading engines...");

  // 1. Initialize LLM
  int32_t mnn_err = 0;
  if (!g_state.llm) {
    LOGI("Creating LLM with model_dir: %s", g_state.model_dir.c_str());
    g_state.llm = mnnr_llm_create(g_state.model_dir.c_str(), &mnn_err);
    if (g_state.llm) {
      uint32_t load_res = mnnr_llm_load(g_state.llm);
      if (load_res != 0) {
        LOGE("LLM load failed with error: %u", load_res);
        mnnr_llm_destroy(g_state.llm);
        g_state.llm = nullptr;
        return false;
      }
      // Configure sampling to prevent repetition loops
      mnnr_llm_set_config(g_state.llm,
        "{\"sampler_type\":\"mixed\","
        "\"mixed_samplers\":[\"topK\",\"topP\",\"temperature\",\"minP\"],"
        "\"temperature\":0.7,"
        "\"topK\":40,"
        "\"topP\":0.9,"
        "\"minP\":0.05,"
        "\"penalty\":1.05,"
        "\"n_gram\":8,"
        "\"ngram_factor\":1.05,"
        "\"max_new_tokens\":280,"
        "\"system_prompt\":\"You are Noor, a warm and knowledgeable Quran companion. "
        "You speak with gentle confidence. You always cite verse references. "
        "You never fabricate verses or scholarly opinions. "
        "If unsure, you say so honestly. Respond in plain text without markdown.\"}");
      LOGI("LLM loaded and configured successfully");
    } else {
      LOGE("Failed to create LLM: %d", mnn_err);
      return false;
    }
  }

  // 2. Initialize Embedding Engine
  if (!ensure_embedding_engine_loaded_locked()) {
    return false;
  }

  // 3. Initialize Zvec Collection
  if (!g_state.collection) {
    int32_t dim = 384;
    if (g_state.embedding_engine) {
      dim = mnnr_embedding_dim(g_state.embedding_engine);
      if (dim <= 0)
        dim = 384;
    }

    open_or_recreate_collection(g_state.collection_path, dim);
  }

  if (g_state.embedding_engine) {
    g_state.cached_embedding_dim = mnnr_embedding_dim(g_state.embedding_engine);
  }

  g_state.engines_loaded = true;
  return true;
}

// Lightweight version: loads only embedding + zvec (skips LLM).
// Used for RAG operations (import, search, list, delete) that don't need the
// LLM.
static bool ensure_rag_engines_loaded() {
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);

  if (!g_state.initialized) {
    LOGE("ensure_rag_engines_loaded: Core not initialized");
    return false;
  }

  // If everything is already loaded, return immediately
  if (g_state.embedding_engine && g_state.collection)
    return true;

  LOGI("Lazy loading RAG engines (embedding + zvec only)...");
  load_deleted_hashes();

  // 1. Initialize Embedding Engine (skip LLM)
  if (!ensure_embedding_engine_loaded_locked()) {
    return false;
  }

  // 2. Initialize Zvec Collection
  if (!g_state.collection) {
    int32_t dim = mnnr_embedding_dim(g_state.embedding_engine);
    if (dim <= 0)
      dim = 384;

    open_or_recreate_collection(g_state.collection_path, dim);
  }

  return g_state.embedding_engine && g_state.collection;
}

FfiResult edgemind_initialize(const char *config_json) {
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
  FfiResult res = {1, 0, nullptr};

  if (g_state.initialized)
    return res;

  std::string config_str = config_json ? config_json : "{}";
  LOGI("Zero-Jank Startup: Deferred heavy loading to background");

  rapidjson::Document doc;
  std::string model_dir, embedding_path, collection_path, whisper_dir;
  bool asr_rnnoise_enabled = false;
  bool prewarm_engines = true;

  if (!doc.Parse(config_str.c_str()).HasParseError()) {
    if (doc.HasMember("data_dir") && doc["data_dir"].IsString())
      model_dir = doc["data_dir"].GetString();

    // Nested parsing for embedding_path
    if (doc.HasMember("models") && doc["models"].IsObject()) {
      const auto &models = doc["models"];
      if (models.HasMember("embedding_path") &&
          models["embedding_path"].IsString()) {
        embedding_path = models["embedding_path"].GetString();
      }
      if (models.HasMember("whisper_dir") &&
          models["whisper_dir"].IsString()) {
        whisper_dir = models["whisper_dir"].GetString();
      }
    }

    if (doc.HasMember("voice") && doc["voice"].IsObject()) {
      const auto &voice = doc["voice"];
      if (voice.HasMember("asr_rnnoise_enabled") &&
          voice["asr_rnnoise_enabled"].IsBool()) {
        asr_rnnoise_enabled = voice["asr_rnnoise_enabled"].GetBool();
      }
    }

    if (doc.HasMember("startup") && doc["startup"].IsObject()) {
      const auto &startup = doc["startup"];
      if (startup.HasMember("prewarm_engines") &&
          startup["prewarm_engines"].IsBool()) {
        prewarm_engines = startup["prewarm_engines"].GetBool();
      }
    }

    // Nested parsing for db_path
    if (doc.HasMember("storage") && doc["storage"].IsObject()) {
      const auto &storage = doc["storage"];
      if (storage.HasMember("db_path") && storage["db_path"].IsString()) {
        collection_path = storage["db_path"].GetString();
      }
    }
  }

  // Normalize paths synchronously (fast)
  if (!model_dir.empty()) {
    model_dir = canonicalize_existing_path(model_dir);
    // Always ensure trailing slash whether or not realpath succeeded.
    // On Android, /data/user/0/ is a symlink to /data/data/ and realpath
    // may fail; without the slash MNN concatenates filenames with no separator.
    if (model_dir.back() != '/')
      model_dir += "/";
  }
  if (collection_path.empty() && !model_dir.empty()) {
    collection_path = model_dir + "zvec_db";
  } else if (!collection_path.empty()) {
    collection_path = canonicalize_existing_path(collection_path);
  }

  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    g_state.model_dir = model_dir;
    g_state.embedding_path = embedding_path;
    g_state.collection_path = collection_path;
    g_state.whisper_dir = whisper_dir;
    g_state.asr_rnnoise_enabled = asr_rnnoise_enabled;
    g_state.initialized.store(true);
  }

  // Background only the heavy engine loading when requested.
  if (prewarm_engines && !model_dir.empty()) {
    std::thread([]() {
      if (!ensure_engines_loaded()) {
        LOGE("Background engine loading failed");
      } else {
        LOGI("Background engine loading complete");
      }
    }).detach();
  } else {
    LOGI("Background engine loading skipped");
  }

  return res;
}

FfiResult edgemind_shutdown() {
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
  if (g_state.llm) {
    mnnr_llm_destroy(g_state.llm);
    g_state.llm = nullptr;
  }
  if (g_state.embedding_engine) {
    mnnr_embedding_destroy(g_state.embedding_engine);
    g_state.embedding_engine = nullptr;
  }
  if (g_state.collection) {
    zvec_close_collection(g_state.collection);
    g_state.collection = nullptr;
  }
  g_state.asr_recognizer.reset();
#ifdef SUPERTONIC_AVAILABLE
  if (g_state.tts_engine) {
    delete g_state.tts_engine;
    g_state.tts_engine = nullptr;
  }
#endif
  g_state.whisper_dir.clear();
  g_state.asr_rnnoise_enabled = false;
  g_state.tts_dir.clear();
  g_state.tts_voice = "F1";
  g_state.engines_loaded = false;
  g_state.cached_embedding_dim = 0;
  g_state.initialized = false;

  FfiResult res = {1, 0, nullptr};
  return res;
}

int32_t edgemind_is_initialized() { return g_state.initialized.load() ? 1 : 0; }

// =============================================================================
// Chat
// =============================================================================

FfiStringResult edgemind_chat(const char *message,
                              const char *conversation_id) {
  MNNR_LLM llm_handle = nullptr;
  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    if (!ensure_engines_loaded() || !g_state.llm) {
      FfiStringResult res = {
          0, -1, allocate_string("LLM not initialized or load failed")};
      return res;
    }
    llm_handle = g_state.llm;
  }

  FfiStringResult res = {1, 0, nullptr};
  char output[4096];
  size_t written =
      mnnr_llm_generate(llm_handle, message, output, sizeof(output), 512);
  if (written > 0) {
    res.value = allocate_string(output);
  } else {
    res.value = allocate_string("Error generating response");
  }

  return res;
}

// Helper for streaming callback
struct StreamCallbackData {
  StreamCallback dart_callback;
  void *user_data;
  std::string full_response;
  MNNR_LLM llm_handle = nullptr;
};

// Check for sentence-level repetition loops in generated text.
// Returns true if any sentence of >=30 chars appears 3+ times.
static bool has_repetition_loop(const std::string &text) {
  if (text.size() < 150) return false;

  // Split on sentence boundaries (period or newline)
  std::vector<std::string> sentences;
  std::string current;
  for (char c : text) {
    if (c == '.' || c == '\n') {
      // Trim whitespace
      size_t start = current.find_first_not_of(" \t\r\n");
      if (start != std::string::npos) {
        std::string trimmed = current.substr(start);
        size_t end = trimmed.find_last_not_of(" \t\r\n");
        if (end != std::string::npos) trimmed = trimmed.substr(0, end + 1);
        if (trimmed.size() >= 30) {
          sentences.push_back(trimmed);
        }
      }
      current.clear();
    } else {
      current += c;
    }
  }

  if (sentences.size() < 4) return false;

  // Check if any of the last 2 sentences repeat 3+ times
  for (size_t i = sentences.size() >= 2 ? sentences.size() - 2 : 0;
       i < sentences.size(); i++) {
    int count = 0;
    for (const auto &s : sentences) {
      if (s == sentences[i]) count++;
    }
    if (count >= 3) return true;
  }
  return false;
}

static void native_stream_callback(const char *token, void *ud) {
  StreamCallbackData *ctx = static_cast<StreamCallbackData *>(ud);
  if (ctx && ctx->dart_callback && token) {
    ctx->full_response += token;

    // Check for repetition loop every ~200 chars
    if (ctx->full_response.size() > 200 &&
        ctx->full_response.size() % 50 < std::strlen(token) + 1) {
      if (has_repetition_loop(ctx->full_response)) {
        LOGI("Repetition loop detected, cancelling generation");
        if (ctx->llm_handle) {
          mnnr_llm_cancel(ctx->llm_handle);
        }
        return;
      }
    }

    const char *allocated_token = allocate_string(token);
    ctx->dart_callback(allocated_token, 0, ctx->user_data);
  }
}

static bool is_explicit_summary_intent(const std::string &query) {
  std::string q = query;
  std::transform(q.begin(), q.end(), q.begin(),
                 [](unsigned char c) { return (char)std::tolower(c); });
  while (!q.empty() && std::isspace((unsigned char)q.front())) {
    q.erase(q.begin());
  }
  if (q.rfind("please summarize", 0) == 0) {
    return true;
  }
  if (q.rfind("summarize ", 0) == 0) {
    return true;
  }
  if (q.rfind("give me a summary", 0) == 0) {
    return true;
  }
  if (q.rfind("summary of ", 0) == 0) {
    return true;
  }
  return false;
}

static std::string trim_copy(const std::string &input) {
  size_t start = 0;
  size_t end = input.size();
  while (start < end && std::isspace((unsigned char)input[start])) {
    start++;
  }
  while (end > start && std::isspace((unsigned char)input[end - 1])) {
    end--;
  }
  return input.substr(start, end - start);
}

static std::string to_lower_copy(const std::string &input) {
  std::string out = input;
  std::transform(out.begin(), out.end(), out.begin(),
                 [](unsigned char c) { return (char)std::tolower(c); });
  return out;
}

static std::vector<std::string>
extract_query_keywords(const std::string &query) {
  std::string q = to_lower_copy(query);
  std::vector<std::string> tokens;
  std::string cur;
  for (char c : q) {
    if (std::isalnum((unsigned char)c)) {
      cur.push_back(c);
    } else if (!cur.empty()) {
      tokens.push_back(cur);
      cur.clear();
    }
  }
  if (!cur.empty()) {
    tokens.push_back(cur);
  }
  static const std::unordered_set<std::string> stop = {
      "is",    "are",   "was",   "were",     "do",        "does",    "did",
      "the",   "a",     "an",    "in",       "on",        "at",      "to",
      "of",    "for",   "and",   "or",       "with",      "this",    "that",
      "these", "those", "book",  "document", "mentioned", "mention", "about",
      "what",  "where", "when",  "which",    "who",       "whom",    "why",
      "how",   "can",   "could", "would",    "should"};
  std::vector<std::string> keywords;
  std::unordered_set<std::string> seen;
  for (const auto &t : tokens) {
    if (t.size() < 3) {
      continue;
    }
    if (stop.find(t) != stop.end()) {
      continue;
    }
    if (seen.insert(t).second) {
      keywords.push_back(t);
    }
  }
  std::sort(keywords.begin(), keywords.end(),
            [](const std::string &a, const std::string &b) {
              return a.size() > b.size();
            });
  if (keywords.size() > 6) {
    keywords.resize(6);
  }
  return keywords;
}

static bool contains_any_keyword(const std::string &text,
                                 const std::vector<std::string> &keywords) {
  if (keywords.empty() || text.empty()) {
    return false;
  }
  std::string text_lc = to_lower_copy(text);
  for (const auto &kw : keywords) {
    if (text_lc.find(kw) != std::string::npos) {
      return true;
    }
  }
  return false;
}

static bool is_mention_style_query(const std::string &query) {
  std::string q = to_lower_copy(query);
  return q.find("mention") != std::string::npos ||
         q.find("contains") != std::string::npos ||
         q.find("contain ") != std::string::npos ||
         q.find("appears") != std::string::npos ||
         q.find("present") != std::string::npos ||
         q.find("is there") != std::string::npos;
}

static std::string
extract_current_question_for_retrieval(const std::string &msg_str) {
  std::string trimmed = trim_copy(msg_str);

  // The new format simply appends "User: " before the final question
  const std::string user_marker = "User: ";
  size_t last_user_pos = trimmed.rfind(user_marker);

  if (last_user_pos != std::string::npos) {
    // If we find "User: ", everything after it is the current question
    return trim_copy(trimmed.substr(last_user_pos + user_marker.size()));
  }

  // Fallbacks for older format just in case
  const std::string marker = "\nCurrent Question: ";
  size_t pos = trimmed.rfind(marker);
  if (pos != std::string::npos) {
    return trim_copy(trimmed.substr(pos + marker.size()));
  }

  const std::string marker_no_newline = "Current Question: ";
  pos = trimmed.rfind(marker_no_newline);
  if (pos != std::string::npos) {
    return trim_copy(trimmed.substr(pos + marker_no_newline.size()));
  }

  return trimmed;
}

static std::string normalize_query_for_cache(const std::string &query);

static std::string extract_conversation_history(const std::string &msg_str) {
  const std::string user_marker = "User: ";
  size_t last_user_pos = msg_str.rfind(user_marker);
  if (last_user_pos == std::string::npos) {
    return "";
  }

  std::string conversation_history = trim_copy(msg_str.substr(0, last_user_pos));
  const std::string history_header = "Previous Conversation:\n";
  if (conversation_history.rfind(history_header, 0) == 0) {
    conversation_history =
        trim_copy(conversation_history.substr(history_header.length()));
  }
  return conversation_history;
}

static std::vector<std::string>
extract_recent_user_turns(const std::string &conversation_history,
                          size_t max_turns) {
  const std::string user_marker = "User: ";
  const std::string assistant_marker = "Assistant: ";
  const std::string &role_marker = user_marker;
  std::vector<std::string> turns;

  size_t search_pos = 0;
  while (search_pos < conversation_history.size()) {
    size_t role_pos = conversation_history.find(role_marker, search_pos);
    if (role_pos == std::string::npos) {
      break;
    }

    size_t content_start = role_pos + role_marker.size();
    size_t next_user = conversation_history.find(user_marker, content_start);
    size_t next_assistant =
        conversation_history.find(assistant_marker, content_start);
    size_t segment_end = conversation_history.size();
    if (next_user != std::string::npos) {
      segment_end = std::min(segment_end, next_user);
    }
    if (next_assistant != std::string::npos) {
      segment_end = std::min(segment_end, next_assistant);
    }
    std::string segment = conversation_history.substr(
        content_start, segment_end == std::string::npos
                           ? std::string::npos
                           : segment_end - content_start);

    segment = trim_copy(segment);
    if (!segment.empty()) {
      turns.push_back(segment);
    }

    if (segment_end == conversation_history.size()) {
      break;
    }
    search_pos = segment_end;
  }

  if (turns.size() > max_turns) {
    turns.erase(turns.begin(), turns.end() - (std::ptrdiff_t)max_turns);
  }
  return turns;
}

static std::vector<std::string>
extract_recent_assistant_turns(const std::string &conversation_history,
                               size_t max_turns) {
  const std::string assistant_marker = "Assistant: ";
  const std::string user_marker = "User: ";
  const std::string &role_marker = assistant_marker;
  std::vector<std::string> turns;

  size_t search_pos = 0;
  while (search_pos < conversation_history.size()) {
    size_t role_pos = conversation_history.find(role_marker, search_pos);
    if (role_pos == std::string::npos) {
      break;
    }

    size_t content_start = role_pos + role_marker.size();
    size_t next_user = conversation_history.find(user_marker, content_start);
    size_t next_assistant =
        conversation_history.find(assistant_marker, content_start);
    size_t segment_end = conversation_history.size();
    if (next_user != std::string::npos) {
      segment_end = std::min(segment_end, next_user);
    }
    if (next_assistant != std::string::npos) {
      segment_end = std::min(segment_end, next_assistant);
    }
    std::string segment = conversation_history.substr(
        content_start, segment_end == std::string::npos
                           ? std::string::npos
                           : segment_end - content_start);

    segment = trim_copy(segment);
    if (!segment.empty()) {
      turns.push_back(segment);
    }

    if (segment_end == conversation_history.size()) {
      break;
    }
    search_pos = segment_end;
  }

  if (turns.size() > max_turns) {
    turns.erase(turns.begin(), turns.end() - (std::ptrdiff_t)max_turns);
  }
  return turns;
}

static bool is_no_answer_response(const std::string &text) {
  std::string normalized = to_lower_copy(text);
  return normalized.find("i could not find this in the documents") !=
             std::string::npos ||
         normalized.find("no relevant documents were found") !=
             std::string::npos;
}

static std::string strip_suggested_questions_section(
    const std::string &text) {
  static const std::vector<std::string> markers = {
      "\n### Suggested Questions", "\n## Suggested Questions",
      "\n# Suggested Questions",   "\nSuggested Questions"};

  size_t cut_pos = std::string::npos;
  for (const auto &marker : markers) {
    size_t pos = text.find(marker);
    if (pos != std::string::npos &&
        (cut_pos == std::string::npos || pos < cut_pos)) {
      cut_pos = pos;
    }
  }

  if (cut_pos == std::string::npos) {
    return trim_copy(text);
  }
  return trim_copy(text.substr(0, cut_pos));
}

static std::string extract_cached_summary_context(
    const std::string &conversation_history, size_t max_chars) {
  std::vector<std::string> assistant_turns =
      extract_recent_assistant_turns(conversation_history, 2);
  for (auto it = assistant_turns.rbegin(); it != assistant_turns.rend(); ++it) {
    if (is_no_answer_response(*it)) {
      continue;
    }
    std::string summary = strip_suggested_questions_section(*it);
    if (summary.empty()) {
      continue;
    }
    if (summary.size() > max_chars) {
      summary.resize(max_chars);
    }
    return trim_copy(summary);
  }
  return "";
}

static void append_context_terms_from_turns(
    const std::vector<std::string> &turns, std::unordered_set<std::string> &seen,
    std::vector<std::string> &context_terms, size_t max_terms,
    bool skip_no_answer_turns) {
  for (auto it = turns.rbegin(); it != turns.rend(); ++it) {
    if (skip_no_answer_turns && is_no_answer_response(*it)) {
      continue;
    }
    std::vector<std::string> turn_keywords = extract_query_keywords(*it);
    for (const auto &term : turn_keywords) {
      if (seen.insert(term).second) {
        context_terms.push_back(term);
        if (context_terms.size() >= max_terms) {
          return;
        }
      }
    }
  }
}

static bool is_context_dependent_query(const std::string &query) {
  std::string q = to_lower_copy(trim_copy(query));
  if (q.empty()) {
    return false;
  }

  static const std::vector<std::string> follow_up_prefixes = {
      "and ",          "what about",     "how about",
      "what else",     "tell me more",   "more on",
      "does it",       "does that",      "does this",
      "is it",         "is that",        "is this",
      "can it",        "can that",       "can this",
      "why does",      "why is",         "where is",
      "when did",      "how does that",  "how does this",
      "how does it",   "what is it",     "what is that",
      "what is this",  "and what",       "and how",
      "and why",       "and where"};

  for (const auto &prefix : follow_up_prefixes) {
    if (q.rfind(prefix, 0) == 0) {
      return true;
    }
  }

  static const std::unordered_set<std::string> context_pronouns = {
      "it",   "this", "that", "they", "them",
      "those", "these", "he",   "she",  "there"};

  std::vector<std::string> keywords = extract_query_keywords(q);
  size_t first_space = q.find(' ');
  std::string first_token =
      first_space == std::string::npos ? q : q.substr(0, first_space);
  if (context_pronouns.find(first_token) != context_pronouns.end()) {
    return true;
  }

  return q.size() <= 32 && keywords.size() <= 2;
}

static std::string join_terms(const std::vector<std::string> &terms,
                              const char *separator) {
  if (terms.empty()) {
    return "";
  }

  std::string joined;
  for (size_t i = 0; i < terms.size(); ++i) {
    if (i > 0) {
      joined += separator;
    }
    joined += terms[i];
  }
  return joined;
}

static std::string rewrite_query_for_retrieval(const std::string &msg_str,
                                               const std::string &query) {
  std::string normalized_query = normalize_query_for_cache(query);
  if (normalized_query.empty() || is_explicit_summary_intent(normalized_query)) {
    return normalized_query;
  }

  std::vector<std::string> current_keywords =
      extract_query_keywords(normalized_query);
  std::string conversation_history = extract_conversation_history(msg_str);
  if (conversation_history.empty()) {
    return normalized_query;
  }

  std::vector<std::string> recent_turns =
      extract_recent_user_turns(conversation_history, 3);
  std::vector<std::string> recent_assistant_turns =
      extract_recent_assistant_turns(conversation_history, 2);

  bool should_expand = is_context_dependent_query(normalized_query) ||
                       current_keywords.size() < 2 || recent_turns.empty();
  if (!should_expand) {
    return normalized_query;
  }

  std::unordered_set<std::string> seen(current_keywords.begin(),
                                       current_keywords.end());
  std::vector<std::string> context_terms;
  append_context_terms_from_turns(recent_turns, seen, context_terms, 5, false);
  if (context_terms.size() < 5) {
    append_context_terms_from_turns(recent_assistant_turns, seen,
                                    context_terms, 5, true);
  }

  if (context_terms.empty()) {
    return normalized_query;
  }

  std::string rewritten = normalized_query +
                          " Context topic: " + join_terms(context_terms, " ");
  LOGI("rewrite_query_for_retrieval: '%s' -> '%s'", normalized_query.c_str(),
       rewritten.c_str());
  return rewritten;
}

static constexpr size_t MAX_EMBEDDING_CACHE_ENTRIES = 128;

static std::vector<std::string>
extract_retrieval_keywords(const std::string &search_query,
                           const std::string &retrieval_query) {
  std::vector<std::string> keywords = extract_query_keywords(search_query);
  if (keywords.empty() && retrieval_query != search_query) {
    keywords = extract_query_keywords(retrieval_query);
  }
  return keywords;
}

static std::string normalize_query_for_cache(const std::string &query) {
  std::string trimmed = trim_copy(query);
  if (trimmed.empty()) {
    return trimmed;
  }

  std::string normalized;
  normalized.reserve(trimmed.size());
  bool previous_was_space = false;
  for (char c : trimmed) {
    if (std::isspace((unsigned char)c)) {
      if (!previous_was_space) {
        normalized.push_back(' ');
      }
      previous_was_space = true;
      continue;
    }
    normalized.push_back(c);
    previous_was_space = false;
  }
  return normalized;
}

static bool get_query_embedding_cached(const std::string &query,
                                       MNNR_Embedding embedding,
                                       int32_t dim,
                                       std::vector<float> &query_vec,
                                       const char *timing_scope) {
  std::string cache_key = normalize_query_for_cache(query);
  if (cache_key.empty()) {
    return false;
  }

  {
    std::lock_guard<std::recursive_mutex> lock(g_state.cache_mutex);
    auto it = g_state.embedding_cache.find(cache_key);
    if (it != g_state.embedding_cache.end() &&
        it->second.size() == (size_t)dim) {
      query_vec = it->second;
      return true;
    }
  }

  std::string prefixed_query = prepare_query_for_embedding(cache_key);
  auto emb_t0 = std::chrono::steady_clock::now();
  size_t generated =
      mnnr_embedding_generate(embedding, prefixed_query.c_str(),
                              query_vec.data(), (size_t)dim);
  if (generated == 0) {
    return false;
  }

  if (timing_scope && edgemind_timing_enabled()) {
    auto emb_t1 = std::chrono::steady_clock::now();
    auto emb_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(emb_t1 - emb_t0)
            .count();
    LOGI("timing %s embedding_ms=%lld query_len=%zu", timing_scope,
         (long long)emb_ms, cache_key.size());
  }

  std::lock_guard<std::recursive_mutex> lock(g_state.cache_mutex);
  if (g_state.embedding_cache.size() >= MAX_EMBEDDING_CACHE_ENTRIES) {
    auto it = g_state.embedding_cache.begin();
    for (size_t n = g_state.embedding_cache.size() / 2;
         n > 0 && it != g_state.embedding_cache.end(); --n) {
      it = g_state.embedding_cache.erase(it);
    }
  }
  g_state.embedding_cache[cache_key] = query_vec;
  return true;
}

static std::string extract_result_title(const ZvecSearchResult &result) {
  if (!result.metadata) {
    return "Unknown";
  }

  rapidjson::Document meta_doc;
  if (meta_doc.Parse(result.metadata).HasParseError()) {
    return "Unknown";
  }

  if (meta_doc.HasMember("title") && meta_doc["title"].IsString()) {
    return meta_doc["title"].GetString();
  }
  return "Unknown";
}

static std::string extract_result_source_type(const ZvecSearchResult &result) {
  if (!result.metadata) return "document";
  rapidjson::Document meta_doc;
  if (meta_doc.Parse(result.metadata).HasParseError()) return "document";
  if (meta_doc.HasMember("source_type") && meta_doc["source_type"].IsString()) {
    return meta_doc["source_type"].GetString();
  }
  return "document";
}

static std::string format_source_label(const ZvecSearchResult &result) {
  std::string title = extract_result_title(result);
  std::string source_type = extract_result_source_type(result);
  if (source_type == "note") {
    return "[Note: " + title + "]";
  }
  return "[Source: " + title + "]";
}

static std::string extract_result_doc_handle(const ZvecSearchResult &result) {
  std::string meta = result.metadata ? std::string(result.metadata) : "{}";
  std::string hash = get_json_string_value(meta, "hash");
  if (!hash.empty()) {
    return hash;
  }
  return result.id ? std::string(result.id) : "";
}

static int count_keyword_hits(const std::string &title,
                              const std::string &content,
                              const std::vector<std::string> &keywords) {
  if (keywords.empty()) {
    return 0;
  }

  std::string title_lc = to_lower_copy(title);
  std::string content_lc = to_lower_copy(content);
  int hits = 0;
  for (const auto &keyword : keywords) {
    if (title_lc.find(keyword) != std::string::npos ||
        content_lc.find(keyword) != std::string::npos) {
      hits++;
    }
  }
  return hits;
}

static int count_content_keyword_hits(const std::string &content,
                                      const std::vector<std::string> &keywords) {
  if (keywords.empty()) {
    return 0;
  }

  std::string content_lc = to_lower_copy(content);
  int hits = 0;
  for (const auto &keyword : keywords) {
    if (content_lc.find(keyword) != std::string::npos) {
      hits++;
    }
  }
  return hits;
}

static int count_content_keyword_hits_lowered(
    const std::string &content_lc,
    const std::vector<std::string> &keywords) {
  if (keywords.empty() || content_lc.empty()) {
    return 0;
  }

  int hits = 0;
  for (const auto &keyword : keywords) {
    if (content_lc.find(keyword) != std::string::npos) {
      hits++;
    }
  }
  return hits;
}

static int compute_candidate_limit(int requested_limit, bool mention_style,
                                   bool has_keywords) {
  int multiplier = mention_style ? 6 : (has_keywords ? 4 : 3);
  int minimum = mention_style ? 18 : 12;
  int maximum = mention_style ? 48 : 32;
  return std::min(std::max(requested_limit * multiplier, minimum), maximum);
}

static ZvecStatus fetch_document_chunks(ZvecCollection coll,
                                        const std::string &doc_id,
                                        int fetch_limit,
                                        ZvecSearchResult **results,
                                        uint32_t *count) {
  if (results) {
    *results = nullptr;
  }
  if (count) {
    *count = 0;
  }
  if (doc_id.empty() || !results || !count || fetch_limit <= 0) {
    return ZVEC_ERROR_INTERNAL;
  }

  std::vector<std::string> chunk_ids_str;
  std::vector<const char *> chunk_ids_ptr;
  chunk_ids_str.reserve((size_t)fetch_limit);
  chunk_ids_ptr.reserve((size_t)fetch_limit);
  const std::string chunk_prefix = chunk_id_prefix_for_hash(doc_id);
  const std::string single_doc_id = sanitize_doc_id_component(doc_id);

  for (int i = 0; i < fetch_limit; ++i) {
    chunk_ids_str.push_back(chunk_prefix + std::to_string(i));
  }
  for (int i = 0; i < fetch_limit; ++i) {
    chunk_ids_ptr.push_back(chunk_ids_str[i].c_str());
  }

  ZvecStatus status =
      zvec_fetch(coll, chunk_ids_ptr.data(), fetch_limit, results, count);
  if ((status != ZVEC_OK || *count == 0) && !doc_id.empty()) {
    if (*results) {
      zvec_free_results(*results, *count);
      *results = nullptr;
      *count = 0;
    }
    const char *single_doc_id_ptr = single_doc_id.c_str();
    status = zvec_fetch(coll, &single_doc_id_ptr, 1, results, count);
  }

  return status;
}

static std::vector<uint32_t>
build_reranked_result_order(const ZvecSearchResult *results, uint32_t count,
                            const std::vector<std::string> &keywords,
                            bool mention_style) {
  std::vector<uint32_t> order;
  order.reserve(count);
  for (uint32_t i = 0; i < count; ++i) {
    order.push_back(i);
  }

  if (count <= 1 || keywords.empty()) {
    return order;
  }

  std::vector<float> rerank_scores(count, 0.0f);
  const float keyword_boost = mention_style ? 0.20f : 0.05f;

  for (uint32_t i = 0; i < count; ++i) {
    std::string title = extract_result_title(results[i]);
    std::string content = results[i].content ? std::string(results[i].content)
                                             : std::string();
    int keyword_hits = count_keyword_hits(title, content, keywords);
    rerank_scores[i] = results[i].score + keyword_hits * keyword_boost;
  }

  std::stable_sort(order.begin(), order.end(),
                   [&](uint32_t lhs, uint32_t rhs) {
                     if (rerank_scores[lhs] == rerank_scores[rhs]) {
                       return results[lhs].score > results[rhs].score;
                     }
                     return rerank_scores[lhs] > rerank_scores[rhs];
                   });
  return order;
}

static std::string execute_search_json(const std::string &query, int32_t limit,
                                       const char *filter,
                                       MNNR_Embedding embedding_handle,
                                       ZvecCollection collection_handle,
                                       int32_t dim) {
  if (query.empty()) {
    return "[]";
  }

  thread_local std::vector<float> query_vec;
  if (query_vec.size() != (size_t)dim) {
    query_vec.resize(dim);
  }

  if (!get_query_embedding_cached(query, embedding_handle, dim, query_vec,
                                  "rag_search")) {
    return "[]";
  }

  std::vector<std::string> keywords = extract_query_keywords(query);
  bool mention_style = is_mention_style_query(query);
  int candidate_limit =
      compute_candidate_limit(limit, mention_style, !keywords.empty());
  float query_threshold = mention_style ? 0.0f : 0.01f;

  ZvecSearchResult *results = nullptr;
  uint32_t count = 0;
  ZvecStatus status = zvec_search_with_threshold(
      collection_handle, query_vec.data(), (uint32_t)dim,
      (uint32_t)candidate_limit, query_threshold, filter, &results, &count);

  if (status != ZVEC_OK || count == 0) {
    if (results && count > 0) {
      zvec_free_results(results, count);
    }
    results = nullptr;
    count = 0;
    status = zvec_search(collection_handle, query_vec.data(), (uint32_t)dim,
                         (uint32_t)candidate_limit, filter, &results, &count);
  }

  if (status != ZVEC_OK || count == 0) {
    return "[]";
  }

  std::vector<uint32_t> order =
      build_reranked_result_order(results, count, keywords, mention_style);

  std::string json = "[\n";
  int emitted = 0;
  for (uint32_t index : order) {
    if (emitted >= limit) {
      break;
    }

    std::string meta = results[index].metadata
                           ? std::string(results[index].metadata)
                           : "{}";
    std::string doc_handle = extract_result_doc_handle(results[index]);
    std::string chunk_id = results[index].id ? std::string(results[index].id)
                                             : std::string();
    std::string safe_content =
        results[index].content ? escape_json_string(results[index].content) : "";

    json += "  {\n";
    json += "    \"doc_id\": \"" + doc_handle + "\",\n";
    json += "    \"chunk_id\": \"" + chunk_id + "\",\n";
    json += "    \"score\": " + std::to_string(results[index].score) + ",\n";
    json += "    \"content\": \"" + safe_content + "\",\n";
    json += "    \"metadata\": " + meta + "\n";
    json += "  }";
    emitted++;
    if (emitted < limit && emitted < (int)order.size()) {
      json += ",";
    }
    json += "\n";
  }
  json += "]";
  zvec_free_results(results, count);
  return emitted > 0 ? json : "[]";
}

// Placeholder for RAG prompt building functions (assumed to be defined
// elsewhere)
static std::string build_rag_prompt_global(const std::string &msg_str,
                                           MNNR_Embedding embedding,
                                           ZvecCollection coll, int32_t dim) {
  auto rag_t0 = std::chrono::steady_clock::now();
  std::string search_query = extract_current_question_for_retrieval(msg_str);
  std::string retrieval_query = rewrite_query_for_retrieval(msg_str, search_query);
  bool summary_intent = is_explicit_summary_intent(search_query);
  LOGI("build_rag_prompt_global: query='%s', is_summary=%d",
       search_query.c_str(), summary_intent ? 1 : 0);

  thread_local std::vector<float> query_vec;
  if (query_vec.size() != (size_t)dim) {
    query_vec.resize((size_t)dim);
  }
  bool have_query_embedding =
      get_query_embedding_cached(retrieval_query, embedding, dim, query_vec,
                                 "rag_global");

  if (!have_query_embedding) {
    LOGW("build_rag_prompt_global: embedding generation failed for query");
  }

  ZvecSearchResult *results = nullptr;
  uint32_t count = 0;
  ZvecStatus status = ZVEC_ERROR_INTERNAL;

  bool is_summary = is_explicit_summary_intent(search_query);
  std::vector<std::string> keywords =
      is_summary ? std::vector<std::string>()
                 : extract_retrieval_keywords(search_query, retrieval_query);
  bool mention_style = !is_summary && is_mention_style_query(search_query);

  int topk = is_summary ? 8 : compute_candidate_limit(6, mention_style,
                                                      !keywords.empty());
  float query_threshold = is_summary ? 0.0f : (mention_style ? 0.0f : 0.02f);
  float selection_threshold = is_summary ? 0.05f : 0.06f;

  const size_t max_context_chars = 6000; // Fit ~1500 tokens of context

  LOGI("build_rag_prompt_global: topk=%d, query_threshold=%.3f, "
       "selection_threshold=%.3f",
       topk, query_threshold, selection_threshold);

  if (have_query_embedding) {
    auto search_t0 = std::chrono::steady_clock::now();
    status = zvec_search_with_threshold(coll, query_vec.data(), (uint32_t)dim,
                                        (uint32_t)topk, query_threshold,
                                        nullptr, &results, &count);
    if (edgemind_timing_enabled()) {
      auto search_t1 = std::chrono::steady_clock::now();
      auto search_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                           search_t1 - search_t0)
                           .count();
      LOGI("timing rag_global search_ms=%lld topk=%d count=%u",
           (long long)search_ms, topk, count);
    }

    LOGI("build_rag_prompt_global: search status=%d, count=%u", status,
         count);
    if (status != ZVEC_OK || count == 0) {
      if (results && count > 0) {
        zvec_free_results(results, count);
      }
      results = nullptr;
      count = 0;
      status = zvec_search(coll, query_vec.data(), (uint32_t)dim,
                           (uint32_t)topk, nullptr, &results, &count);
      LOGI("build_rag_prompt_global: fallback search status=%d, count=%u",
           status, count);
    }
  }

  std::string conversation_history = extract_conversation_history(msg_str);

  std::string context_str;
  context_str.reserve(max_context_chars + 256);
  bool added_context = false;
  int added_count = 0;
  int skipped_count = 0;
  std::vector<uint32_t> ordered_indices =
      build_reranked_result_order(results, count, keywords, mention_style);

  for (uint32_t index : ordered_indices) {
    if (results[index].score < selection_threshold) {
      skipped_count++;
      continue;
    }

    context_str += format_source_label(results[index]) + "\n";
    if (results[index].content) {
      context_str += results[index].content;
      context_str += "\n\n";
      added_count++;
    }
    added_context = true;
    if (context_str.size() >= max_context_chars) break;
  }

  LOGI("build_rag_prompt_global: added %d chunks, skipped %d chunks "
       "(threshold=%.3f)",
       added_count, skipped_count, selection_threshold);

  if (!added_context && is_summary) {
    uint32_t fallback_limit = count < (uint32_t)topk ? count : (uint32_t)topk;
    for (uint32_t n = 0; n < fallback_limit; ++n) {
      uint32_t index = ordered_indices[n];
      if (!results[index].content || std::strlen(results[index].content) == 0)
        continue;
      context_str += format_source_label(results[index]) + "\n";
      context_str += results[index].content;
      context_str += "\n\n";
      added_context = true;
      if (context_str.size() >= max_context_chars) break;
    }
  } else if (!added_context && !is_summary && count > 0) {
    int fallback_added = 0;
    for (uint32_t index : ordered_indices) {
      if (!results[index].content || std::strlen(results[index].content) == 0) {
        continue;
      }
      context_str += format_source_label(results[index]) + "\n";
      context_str += results[index].content;
      context_str += "\n\n";
      added_context = true;
      fallback_added++;
      if (fallback_added >= 2 || context_str.size() >= max_context_chars) {
        break;
      }
    }
  }

  std::string final_prompt;
  final_prompt.reserve(768 + conversation_history.size() + search_query.size() +
                       context_str.size());
  final_prompt =
      "You are EdgeDox, a private on-device AI assistant.\n"
      "Be concise and accurate. Use markdown when helpful.\n\n";

    const char *rag_guidance_with_context =
      "Use the document context as your primary grounding and mention or quote "
      "specific details from it when relevant. If the documents do not fully "
      "answer the question, you may continue with general knowledge, reasoning, "
      "or opinion, but clearly distinguish what is document-backed from what is "
      "your own broader answer. Do not pretend unsupported claims came from the "
      "documents.\n";

    const char *rag_guidance_without_context =
      "No relevant document context was found for this query. Answer as helpfully "
      "as you can using general knowledge or reasoned opinion, and briefly note "
      "that the answer is not grounded in the loaded documents.\n";

  if (!conversation_history.empty()) {
    final_prompt +=
        "## Conversation History:\n" + conversation_history + "\n\n";
  }

  final_prompt += "User: " + search_query + "\n\n";

  if (added_context) {
    final_prompt += "## DOCUMENT CONTEXT:\n";
    final_prompt += "<context>\n";
    final_prompt += context_str;
    final_prompt += "</context>\n\n";
    final_prompt += rag_guidance_with_context;
  } else {
    final_prompt += rag_guidance_without_context;
  }

  LOGI("build_rag_prompt_global: built prompt len=%zu, context=%d",
       final_prompt.length(), added_context ? 1 : 0);
  LOGI("rag_telemetry global: chunks_added=%d chunks_skipped=%d "
       "context_chars=%zu top_score=%.3f",
       added_count, skipped_count, context_str.size(),
       count > 0 ? results[0].score : 0.0f);
  zvec_free_results(results, count);
  return final_prompt;
}

static std::string build_rag_prompt_scoped(const std::string &msg_str,
                                           const std::string &doc_id,
                                           MNNR_Embedding embedding,
                                           ZvecCollection coll, int32_t dim) {
  auto rag_t0 = std::chrono::steady_clock::now();
  std::string search_query = extract_current_question_for_retrieval(msg_str);
  std::string retrieval_query = rewrite_query_for_retrieval(msg_str, search_query);
  bool summary_intent = is_explicit_summary_intent(search_query);
  LOGI("build_rag_prompt_scoped: query='%s', doc_id='%s', is_summary=%d",
       search_query.c_str(), doc_id.c_str(), summary_intent ? 1 : 0);

  thread_local std::vector<float> query_vec;
  if (query_vec.size() != (size_t)dim) {
    query_vec.resize((size_t)dim);
  }

  bool is_initial_summary = search_query.empty();
  bool is_summary =
      is_initial_summary || is_explicit_summary_intent(search_query);

  bool have_query_embedding = is_summary;
  if (!is_summary) {
    have_query_embedding = get_query_embedding_cached(retrieval_query, embedding,
                                                      dim, query_vec,
                                                      "rag_scoped");
    if (!have_query_embedding) {
      LOGW("build_rag_prompt_scoped: embedding generation failed for query");
    }
  }

  ZvecSearchResult *results = nullptr;
  uint32_t count = 0;
  ZvecStatus status = ZVEC_ERROR_INTERNAL;
  bool used_doc_fetch_fallback = false;

  // bool is_summary already declared above
  // In scoped mode the hash filter already constrains results to the target
  // document, so there is no cross-document noise to filter out.  Use very
  // relaxed thresholds to avoid discarding relevant chunks whose semantic
  // score happens to be low (common for short factual questions against long
  // technical documents).  A higher topk ensures small documents are fully
  // covered.
  int topk = 40;
  float selection_threshold = 0.0f;
  float query_threshold = -1.0f;

  if (is_summary) {
    topk = 50;                   // Fetch more for summary
    selection_threshold = 0.0f;  // Accept all for summary
    query_threshold = -3.4e38f;  // Allow all candidates; rank in post-filter
  }

  std::string filter = "hash = '" + escape_filter_literal(doc_id) + "'";
  // Query threshold controls coarse candidate retrieval, while
  // selection_threshold is applied when assembling context.
  LOGI(
      "build_rag_prompt_scoped: topk=%d, selection_threshold=%.3f, filter='%s'",
      topk, selection_threshold, filter.c_str());

  if (is_summary) {
    LOGI("build_rag_prompt_scoped: Summary mode - asking for all chunks via "
         "zvec_fetch to sort them locally.");
    auto search_t0 = std::chrono::steady_clock::now();
    status = fetch_document_chunks(coll, doc_id, 30, &results, &count);
    if (edgemind_timing_enabled()) {
      auto search_t1 = std::chrono::steady_clock::now();
      auto search_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                           search_t1 - search_t0)
                           .count();
      LOGI("timing rag_scoped fetch_ms=%lld count=%u", (long long)search_ms,
           count);
    }
    LOGI("build_rag_prompt_scoped: zvec_fetch status=%d, count=%u", status,
         count);
  } else if (have_query_embedding) {
    auto search_t0 = std::chrono::steady_clock::now();
    status = zvec_search_with_threshold(coll, query_vec.data(), (uint32_t)dim,
                                        (uint32_t)topk, query_threshold,
                                        filter.c_str(), &results, &count);
    if (edgemind_timing_enabled()) {
      auto search_t1 = std::chrono::steady_clock::now();
      auto search_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                           search_t1 - search_t0)
                           .count();
      LOGI("timing rag_scoped search_ms=%lld topk=%d count=%u",
           (long long)search_ms, topk, count);
    }
    LOGI("build_rag_prompt_scoped: search status=%d, count=%u", status, count);
    if (status != ZVEC_OK || count == 0) {
      if (results && count > 0) {
        zvec_free_results(results, count);
      }
      results = nullptr;
      count = 0;
      status = zvec_search(coll, query_vec.data(), (uint32_t)dim,
                           (uint32_t)topk, filter.c_str(), &results, &count);
      LOGI("build_rag_prompt_scoped: fallback search status=%d, count=%u",
           status, count);
    }
    if ((status != ZVEC_OK || count == 0) && !doc_id.empty()) {
      if (results && count > 0) {
        zvec_free_results(results, count);
      }
      results = nullptr;
      count = 0;
      status = fetch_document_chunks(coll, doc_id, 80, &results, &count);
      used_doc_fetch_fallback = (status == ZVEC_OK && count > 0);
      LOGI("build_rag_prompt_scoped: doc fetch fallback status=%d, count=%u",
           status, count);
    }
  } else {
    LOGI("build_rag_prompt_scoped: skipping semantic search due to embedding failure");
    if (!doc_id.empty()) {
      status = fetch_document_chunks(coll, doc_id, 80, &results, &count);
      used_doc_fetch_fallback = (status == ZVEC_OK && count > 0);
      LOGI("build_rag_prompt_scoped: embedding-failure fetch status=%d, count=%u",
           status, count);
    }
  }

  if (status == ZVEC_OK && count > 0) {
    std::string conversation_history = extract_conversation_history(msg_str);

    const size_t max_context_chars = 6000;
    std::string context_str;
    context_str.reserve(max_context_chars + 256);
    const int max_chunks = is_summary ? 10 : 8;
    bool added_context = false;

    int skipped_count = 0;
    int added_count = 0;

    // For summary, we collect matching results first to sort them by chunk id
    // This allows sequential concatenation of the document.
    struct ChunkData {
      int index;
      std::string title;
      std::string content;
      std::string content_lc;
      std::string chunk_id;
      float score;
    };
    std::vector<ChunkData> ordered_chunks;
    ordered_chunks.reserve(count);

    for (uint32_t i = 0; i < count; ++i) {
      rapidjson::Document meta_doc;
      bool has_meta = false;
      if (results[i].metadata) {
        has_meta = !meta_doc.Parse(results[i].metadata).HasParseError();
      }

      std::string hash = "";
      if (has_meta && meta_doc.HasMember("hash") &&
          meta_doc["hash"].IsString()) {
        hash = meta_doc["hash"].GetString();
      }

      bool matches_doc = (hash == doc_id);
      int chunk_idx = -1;

      if (!matches_doc && results[i].id) {
        std::string chunk_id = results[i].id;
        std::string prefix = chunk_id_prefix_for_hash(doc_id);
        if (chunk_id.rfind(prefix, 0) == 0) {
          matches_doc = true;
          try {
            chunk_idx = std::stoi(chunk_id.substr(prefix.length()));
          } catch (...) {
            chunk_idx = 999999;
          }
        }
      } else if (matches_doc && results[i].id) {
        std::string chunk_id = results[i].id;
        std::string prefix = chunk_id_prefix_for_hash(doc_id);
        if (chunk_id.rfind(prefix, 0) == 0) {
          try {
            chunk_idx = std::stoi(chunk_id.substr(prefix.length()));
          } catch (...) {
            chunk_idx = 999999;
          }
        } else {
          chunk_idx = 0; // single chunk doc
        }
      }

      bool allow_by_filter = (!is_summary && !doc_id.empty());
      if (!matches_doc && !allow_by_filter) {
        continue;
      }

      if (!is_summary && !used_doc_fetch_fallback &&
          results[i].score < selection_threshold) {
        skipped_count++;
        continue;
      }

      if (results[i].content && std::strlen(results[i].content) > 0) {
        std::string title = "Document";
        if (has_meta && meta_doc.HasMember("title") &&
            meta_doc["title"].IsString()) {
          title = meta_doc["title"].GetString();
        }
        std::string content = std::string(results[i].content);
        std::string cid = results[i].id ? std::string(results[i].id) : "";
        ordered_chunks.push_back(
            {chunk_idx, std::move(title), std::move(content), std::string(),
             std::move(cid), results[i].score});
        ordered_chunks.back().content_lc =
            to_lower_copy(ordered_chunks.back().content);
      }
    }

    if (is_summary || used_doc_fetch_fallback) {
      // Sort chunks sequentially for summarizing
      std::sort(ordered_chunks.begin(), ordered_chunks.end(),
                [](const ChunkData &a, const ChunkData &b) {
                  return a.index < b.index;
                });
    }

    std::vector<std::string> keywords =
        is_summary ? std::vector<std::string>()
                   : extract_retrieval_keywords(search_query, retrieval_query);
    bool mention_style = is_mention_style_query(search_query);
    bool semantic_has_content_keyword_hit = false;
    if (!keywords.empty()) {
      for (const auto &chunk : ordered_chunks) {
        if (count_content_keyword_hits_lowered(chunk.content_lc, keywords) > 0) {
          semantic_has_content_keyword_hit = true;
          break;
        }
      }
    }

    // Keyword-boost reranking: move chunks containing query keywords to the
    // front while preserving relative order within each group
    if (!is_summary && !keywords.empty() && ordered_chunks.size() > 1) {
      std::vector<ChunkData> keyword_hits;
      std::vector<ChunkData> no_hits;
      keyword_hits.reserve(ordered_chunks.size());
      no_hits.reserve(ordered_chunks.size());
      for (auto &c : ordered_chunks) {
        if (count_content_keyword_hits_lowered(c.content_lc, keywords) > 0) {
          keyword_hits.push_back(std::move(c));
        } else {
          no_hits.push_back(std::move(c));
        }
      }
      if (!keyword_hits.empty() && !no_hits.empty()) {
        ordered_chunks.clear();
        ordered_chunks.reserve(keyword_hits.size() + no_hits.size());
        for (auto &c : keyword_hits)
          ordered_chunks.push_back(std::move(c));
        for (auto &c : no_hits)
          ordered_chunks.push_back(std::move(c));
        LOGI("build_rag_prompt_scoped: keyword rerank boosted %zu chunks",
             keyword_hits.size());
      }
    }

    if (!is_summary && !search_query.empty() && !doc_id.empty() &&
        !keywords.empty() && !semantic_has_content_keyword_hit) {
      std::vector<ChunkData> lexical_chunks;
      lexical_chunks.reserve(12);
      {
        ZvecSearchResult *fetch_results = nullptr;
        uint32_t fetch_count = 0;
        const int FETCH_LIMIT = 80;
        std::vector<std::string> chunk_ids_str;
        std::vector<const char *> chunk_ids_ptr;
        chunk_ids_str.reserve(FETCH_LIMIT);
        chunk_ids_ptr.reserve(FETCH_LIMIT);
        const std::string chunk_prefix = chunk_id_prefix_for_hash(doc_id);
        for (int i = 0; i < FETCH_LIMIT; ++i) {
          chunk_ids_str.push_back(chunk_prefix + std::to_string(i));
        }
        for (int i = 0; i < FETCH_LIMIT; ++i) {
          chunk_ids_ptr.push_back(chunk_ids_str[i].c_str());
        }
        ZvecStatus fetch_status =
            zvec_fetch(coll, chunk_ids_ptr.data(), FETCH_LIMIT, &fetch_results,
                       &fetch_count);
        if (fetch_status == ZVEC_OK && fetch_count > 0) {
          int lexical_added = 0;
          for (uint32_t i = 0; i < fetch_count; ++i) {
            if (!fetch_results[i].content ||
                std::strlen(fetch_results[i].content) == 0) {
              continue;
            }
            int chunk_idx = 999999;
            if (fetch_results[i].id) {
              std::string chunk_id = std::string(fetch_results[i].id);
              std::string prefix = chunk_id_prefix_for_hash(doc_id);
              if (chunk_id.rfind(prefix, 0) == 0) {
                try {
                  chunk_idx = std::stoi(chunk_id.substr(prefix.length()));
                } catch (...) {
                  chunk_idx = 999999;
                }
              }
            }
            std::string meta = fetch_results[i].metadata
                                   ? std::string(fetch_results[i].metadata)
                                   : "{}";
            std::string title = "Document";
            std::string extracted_title = get_json_string_value(meta, "title");
            if (!extracted_title.empty()) {
              title = extracted_title;
            }
            std::string content = std::string(fetch_results[i].content);
            std::string content_lc = to_lower_copy(content);
            if (count_content_keyword_hits_lowered(content_lc, keywords) == 0) {
              continue;
            }
            lexical_chunks.push_back(
                {chunk_idx,
                 std::move(title),
                 std::move(content),
                 std::move(content_lc),
                 fetch_results[i].id ? std::string(fetch_results[i].id) : "",
                 0.0f});
            lexical_added++;
            if (lexical_added >= 6) {
              break;
            }
          }
          if (!lexical_chunks.empty()) {
            std::sort(lexical_chunks.begin(), lexical_chunks.end(),
                      [](const ChunkData &a, const ChunkData &b) {
                        return a.index < b.index;
                      });
            // Deduplicate: skip semantic chunks already in lexical set
            std::unordered_set<std::string> seen_ids;
            for (const auto &lc : lexical_chunks) {
              if (!lc.chunk_id.empty()) seen_ids.insert(lc.chunk_id);
            }
            for (const auto &sc : ordered_chunks) {
              if (sc.chunk_id.empty() || seen_ids.find(sc.chunk_id) == seen_ids.end()) {
                lexical_chunks.push_back(sc);
              }
            }
            ordered_chunks.swap(lexical_chunks);
          }
          LOGI("build_rag_prompt_scoped: lexical fallback added %d chunks "
               "(keywords=%zu, mention_style=%d)",
               lexical_added, keywords.size(), mention_style ? 1 : 0);
        }
        if (fetch_results) {
          zvec_free_results(fetch_results, fetch_count);
        }
      }
    }

    if (!is_summary && ordered_chunks.empty() && count > 0) {
      int fallback_added = 0;
      for (uint32_t i = 0; i < count && fallback_added < 2; ++i) {
        if (!results[i].content || std::strlen(results[i].content) == 0) {
          continue;
        }
        std::string meta =
            results[i].metadata ? std::string(results[i].metadata) : "{}";
        std::string title = "Document";
        std::string extracted_title = get_json_string_value(meta, "title");
        if (!extracted_title.empty()) {
          title = extracted_title;
        }
        std::string content = std::string(results[i].content);
        ordered_chunks.push_back(
            {0,
             std::move(title),
             std::move(content),
             std::string(),
             results[i].id ? std::string(results[i].id) : "",
             results[i].score});
        ordered_chunks.back().content_lc =
            to_lower_copy(ordered_chunks.back().content);
        fallback_added++;
      }
      LOGI("build_rag_prompt_scoped: fallback added %d chunks for "
           "low-similarity query",
           fallback_added);
    }

    for (const auto &chunk : ordered_chunks) {
      if (context_str.size() >= max_context_chars ||
          added_count >= max_chunks) {
        break;
      }
      // Use [Note: ...] label for notes (hash starts with "note_")
      std::string label = (doc_id.rfind("note_", 0) == 0) ? "[Note: " : "[Source: ";
      context_str += label + chunk.title + "]\n";
      context_str += chunk.content + "\n\n";
      added_count++;
      added_context = true;
    }

    if (!is_summary && !added_context && !conversation_history.empty()) {
      std::string cached_summary_context =
          extract_cached_summary_context(conversation_history,
                                         max_context_chars / 2);
      if (!cached_summary_context.empty()) {
        context_str += "[Source: Cached Summary]\n";
        context_str += cached_summary_context;
        context_str += "\n\n";
        added_context = true;
        added_count++;
        LOGI("build_rag_prompt_scoped: appended cached summary fallback "
             "len=%zu",
             cached_summary_context.size());
      }
    }

    LOGI("build_rag_prompt_scoped: added %d chunks, skipped %d chunks "
         "(threshold=%.3f)",
         added_count, skipped_count, selection_threshold);

    std::string final_prompt;
    final_prompt.reserve(896 + conversation_history.size() +
               search_query.size() + context_str.size());
    final_prompt =
        "You are EdgeDox, a private on-device AI assistant.\n"
        "Be concise and accurate. Use markdown when helpful.\n\n";

    const char *rag_guidance_with_context =
      "Use the document context as your primary grounding and mention or "
      "quote specific details from it when relevant. If the document does "
      "not fully answer the question, you may continue with general "
      "knowledge, reasoning, or opinion, but clearly distinguish what is "
      "document-backed from what is your own broader answer. Do not pretend "
      "unsupported claims came from the document.\n";

    const char *rag_guidance_without_context =
      "No relevant document context was found. Answer as helpfully as you can "
      "using general knowledge or reasoned opinion, and briefly note that the "
      "answer is not grounded in the loaded document context.\n";

    if (is_summary) {
      final_prompt +=
          "Summarize the document context below. Include main topics, "
          "key points, and important details using bullet points.\n"
          "After the summary, list exactly 3 follow-up questions under "
          "'Suggested Questions'. Each question must be self-contained, "
          "reference specific names/terms from the document, and end "
          "with a question mark.\n\n";
      if (search_query.empty() || is_initial_summary) {
        final_prompt +=
            "User: Summarize this document and suggest three "
            "follow-up questions.\n\n";
      } else {
        final_prompt += "User: " + search_query + "\n\n";
      }
    } else {
      if (!conversation_history.empty()) {
        final_prompt += "## Conversation History:\n" + conversation_history + "\n\n";
      }
      final_prompt += "User: " + search_query + "\n\n";
    }

    if (added_context) {
      final_prompt += "## DOCUMENT CONTEXT:\n";
      final_prompt += "<context>\n";
      final_prompt += context_str;
      final_prompt += "</context>\n\n";
      final_prompt += rag_guidance_with_context;
    } else {
      final_prompt += rag_guidance_without_context;
    }

    LOGI("build_rag_prompt_scoped: built prompt len=%zu, context=%d",
         final_prompt.length(), added_context ? 1 : 0);
    LOGI("rag_telemetry scoped: chunks_added=%d chunks_skipped=%d "
         "context_chars=%zu doc_id='%s'",
         added_count, skipped_count, context_str.size(), doc_id.c_str());
    zvec_free_results(results, count);
    return final_prompt;
  }
  // Fallback if RAG search failed or no valid matches
  std::string fallback_prompt =
      "You are EdgeDox, a private on-device AI assistant.\n"
      "Be concise and accurate. Use markdown when helpful.\n\n";

  std::string fallback_history = extract_conversation_history(msg_str);
  std::string cached_summary_context =
      extract_cached_summary_context(fallback_history, 3000);
  if (!cached_summary_context.empty()) {
    fallback_prompt += "## DOCUMENT CONTEXT:\n<context>\n";
    fallback_prompt += "[Source: Cached Summary]\n";
    fallback_prompt += cached_summary_context;
    fallback_prompt += "\n</context>\n\n";
  }

  // Extract history for fallback too
  const std::string user_marker = "User: ";
  size_t last_user_pos = msg_str.rfind(user_marker);
  if (last_user_pos != std::string::npos) {
    fallback_prompt += "## Conversation History:\n" +
                       msg_str.substr(0, last_user_pos) + "\n\n";
    fallback_prompt +=
        "User: " + msg_str.substr(last_user_pos + user_marker.length());
  } else {
    fallback_prompt += "User: " + msg_str;
  }

  if (!cached_summary_context.empty()) {
    fallback_prompt +=
        "\n\nUse the document context as your primary grounding and quote or "
        "reference specific details from it when relevant. If the cached "
        "summary does not fully answer the question, you may continue with "
        "general knowledge, reasoning, or opinion, but clearly distinguish "
        "what is summary-backed from what is your own broader answer.\n";
  } else {
    fallback_prompt +=
        "\n\nNo relevant document context was found. Answer as helpfully as "
        "you can using general knowledge or reasoned opinion, and briefly note "
        "that the answer is not grounded in loaded documents.\n";
  }

  return fallback_prompt;
}

FfiResult edgemind_chat_stream(const char *message, const char *conversation_id,
                               int32_t thinking_enabled, int32_t use_documents,
                               const char *focused_doc_id,
                               StreamCallback callback, void *user_data) {
  FfiResult res = {1, 0, nullptr};

  // Copy parameters for the thread
  std::string msg_str = message ? message : "";
  std::string conv_id = conversation_id ? conversation_id : "default";
  bool do_rag = (use_documents != 0);
  std::string doc_id = focused_doc_id ? focused_doc_id : "";

  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    if (!g_state.initialized || !callback) {
      res.success = 0;
      g_chat_active.store(false);
      return res;
    }
  }

  g_chat_active.store(true);

  std::thread([msg_str, conv_id, do_rag, doc_id, callback, user_data]() {
    if (!ensure_engines_loaded()) {
      callback(allocate_string(
                   "The AI engine is still warming up. Please try again in a moment."),
               0, user_data);
      callback(allocate_string(""), 1, user_data);
      g_chat_active.store(false);
      return;
    }

    MNNR_LLM llm = nullptr;
    MNNR_Embedding embedding = nullptr;
    ZvecCollection coll = nullptr;
    int32_t dim = 0;
    {
      std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
      llm = g_state.llm;
      embedding = g_state.embedding_engine;
      coll = g_state.collection;
      dim = resolve_embedding_dim();

      if (!llm) {
        callback(allocate_string(
                     "The AI engine could not be initialized on this device."),
                 0, user_data);
        callback(allocate_string(""), 1, user_data);
        g_chat_active.store(false);
        return;
      }

      if (g_state.active_session_id != conv_id) {
        mnnr_llm_reset(llm);
        g_state.active_session_id = conv_id;
      }
    }

    std::string final_prompt = msg_str;

    if (do_rag && coll && embedding) {
      if (doc_id.empty()) {
        final_prompt = build_rag_prompt_global(msg_str, embedding, coll, dim);
      } else {
        final_prompt =
            build_rag_prompt_scoped(msg_str, doc_id, embedding, coll, dim);
      }
    }

    LOGI("edgemind_chat_stream: final prompt length=%zu, has_rag=%d, "
         "doc_id='%s'",
         final_prompt.length(), do_rag && coll && embedding ? 1 : 0,
         doc_id.c_str());

    // Capture standard callback
    StreamCallbackData cb_data;
    cb_data.dart_callback = callback;
    cb_data.user_data = user_data;
    cb_data.full_response.reserve(1024);
    cb_data.llm_handle = llm;

    int status = mnnr_llm_generate_stream(
        llm, final_prompt.c_str(), native_stream_callback, &cb_data, 1024);

    if (status != 0 && cb_data.full_response.empty()) {
      callback(allocate_string(
                   "I could not generate a response right now. Please try again."),
               0, user_data);
    }

    // Signal EOF with an allocated empty string (is_final = 1)
    callback(allocate_string(""), 1, user_data);
    g_chat_active.store(false);
  }).detach();

  return res;
}

FfiResult edgemind_cancel_generation() {
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
  FfiResult res = {1, 0, nullptr};

  if (g_state.llm) {
    LOGI("edgemind_cancel_generation: signaling cancellation");
    mnnr_llm_cancel(g_state.llm);
  }

  return res;
}

// =============================================================================
// System & Utilities
// =============================================================================

const char *edgemind_version() { return allocate_string("1.0.0-mnn-zvec"); }

int32_t edgemind_mnn_available() { return mnnr_is_available(); }

const char *edgemind_mnn_version() {
  return allocate_string(mnnr_get_version());
}

void edgemind_free_string(const char *s) {
  if (s) {
    free((void *)s);
  }
}

void edgemind_register_dart_callbacks(StreamCallback llm_cb,
                                      StreamCallback asr_cb) {
  std::lock_guard<std::recursive_mutex> lock(g_dart_cb_mutex);
  g_dart_llm_cb = llm_cb;
  g_dart_asr_cb = asr_cb;
}

void edgemind_unregister_dart_callbacks() {
  std::lock_guard<std::recursive_mutex> lock(g_dart_cb_mutex);
  g_dart_llm_cb = nullptr;
  g_dart_asr_cb = nullptr;
}

intptr_t edgemind_memory_usage() {
  if (g_state.llm) {
    return (intptr_t)mnnr_get_memory_usage_llm(g_state.llm);
  }
  return 0;
}

// =============================================================================
// RAG & Knowledge Base
// =============================================================================

FfiStringResult edgemind_add_source(const char *content, const char *metadata) {
  FfiStringResult res = {1, 0, nullptr};

  if (!content || std::strlen(content) == 0) {
    res.success = 0;
    res.value = allocate_string("content is required");
    return res;
  }

  MNNR_Embedding embedding_handle = nullptr;
  ZvecCollection coll_handle = nullptr;
  int32_t dim = 0;

  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    if (!ensure_rag_engines_loaded() || !g_state.collection ||
        !g_state.embedding_engine) {
      res.success = 0;
      res.value = allocate_string("Engines not initialized or load failed");
      return res;
    }
    embedding_handle = g_state.embedding_engine;
    coll_handle = g_state.collection;
    dim = resolve_embedding_dim();
  }

  std::string meta_str = metadata ? metadata : "{}";
  std::string id = get_json_string_value(meta_str, "hash");
  if (id.empty()) {
    auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                      std::chrono::system_clock::now().time_since_epoch())
                      .count();
    id = "doc_" + std::to_string(now_ms) + "_" + std::to_string(rand() % 10000);
  }
  std::string metadata_with_hash = ensure_metadata_hash(meta_str, id);
  const std::string storage_id = sanitize_doc_id_component(id);

  std::vector<float> vector(dim);
  size_t generated = mnnr_embedding_generate(embedding_handle, content,
                                             vector.data(), (size_t)dim);

  if (generated == 0) {
    res.success = 0;
    res.value = allocate_string("Failed to generate embedding");
    return res;
  }

  LOGI("Inserting doc '%s' as storage id '%s' with dim %d", id.c_str(),
       storage_id.c_str(), dim);

  ZvecStatus status =
      zvec_insert(coll_handle, storage_id.c_str(), vector.data(), (uint32_t)dim,
                  content, metadata_with_hash.c_str(), id.c_str());
  if (status == ZVEC_OK) {
    zvec_flush(coll_handle);
    zvec_optimize(coll_handle);
    upsert_source_index(id, metadata_with_hash);
    res.value = allocate_string(id.c_str());
  } else {
    res.success = 0;
    res.value = allocate_string(zvec_get_last_error());
  }

  return res;
}

FfiStringResult edgemind_list_sources() {
  ZvecCollection coll = nullptr;
  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    if (!ensure_rag_engines_loaded() || !g_state.collection) {
      return {1, 0, allocate_string("[]")};
    }
    coll = g_state.collection;
  }

  {
    std::lock_guard<std::recursive_mutex> lock(g_state.sources_mutex);
    if (g_state.deleted_hashes.empty()) {
      // Internal load_deleted_hashes() handles its own lock
    }
    load_deleted_hashes();
  }

  uint64_t total_docs = 0;
  zvec_count(coll, &total_docs);

  std::unordered_map<std::string, std::string> source_entries;
  bool has_index = load_sources_index(source_entries);

  if (total_docs == 0) {
    if (has_index && !source_entries.empty()) {
      clear_source_index();
    }
    return {1, 0, allocate_string("[]")};
  }

  if (has_index) {
    std::string json = "[";
    bool first = true;
    std::lock_guard<std::recursive_mutex> lock(g_state.sources_mutex);
    for (const auto &kv : source_entries) {
      if (g_state.deleted_hashes.count(kv.first)) {
        continue;
      }
      if (!first)
        json += ",";
      first = false;
      json += "[\"" + kv.first + "\", " + kv.second + "]";
    }
    json += "]";
    return {1, 0, allocate_string(json)};
  }

  int32_t dim = resolve_embedding_dim();
  ZvecSearchResult *results = nullptr;
  uint32_t count = 0;
  ZvecStatus status = zvec_list_sources(coll, (uint32_t)dim, &results, &count);
  if (status != ZVEC_OK || count == 0) {
    return {1, 0, allocate_string("[]")};
  }

  std::string json = "[";
  std::unordered_set<std::string> seen_hashes;
  bool first = true;
  for (uint32_t i = 0; i < count; ++i) {
    std::string metadata = results[i].metadata ? results[i].metadata : "{}";
    std::string hash = get_json_string_value(metadata, "hash");
    {
      std::lock_guard<std::recursive_mutex> lock(g_state.sources_mutex);
      if (hash.empty() || g_state.deleted_hashes.count(hash) ||
          !seen_hashes.insert(hash).second) {
        continue;
      }
    }
    upsert_source_index(hash, metadata);
    if (!first)
      json += ",";
    first = false;
    json += "[\"" + hash + "\", " + metadata + "]";
  }
  json += "]";
  zvec_free_results(results, count);
  return {1, 0, allocate_string(json)};
}

FfiResult edgemind_delete_source(const char *doc_id) {
  ZvecCollection coll = nullptr;
  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    if (!ensure_rag_engines_loaded() || !g_state.collection) {
      return {0, -1,
              allocate_string("Not initialized or engines failed to load")};
    }
    coll = g_state.collection;
  }

  if (!doc_id || std::strlen(doc_id) == 0) {
    return {0, -1, allocate_string("doc_id is required")};
  }

  std::string hash(doc_id);

  if (hash == "all") {
    LOGI("edgemind_delete_source: dropping entire collection");
    zvec_destroy(g_state.collection);
    g_state.collection = nullptr;

    // Delete persistence directory
    delete_directory(g_state.collection_path);

    // Also clear deleted hashes cache
    g_state.deleted_hashes.clear();
    save_deleted_hashes();
    clear_source_index();

    // Recreate
    int32_t dim = resolve_embedding_dim();
    if (zvec_create_collection(g_state.collection_path.c_str(), "edgemind",
                               (uint32_t)dim, &g_state.collection) != ZVEC_OK) {
      LOGE("edgemind_delete_source: failed to recreate collection");
      return {0, -1, allocate_string("Failed to recreate collection")};
    }
  } else {
    // Add to soft-deleted cache so UI immediately drops it
    g_state.deleted_hashes.insert(hash);
    save_deleted_hashes();

    // Still attempt true native deletion via best-effort cleanup
    LOGI("edgemind_delete_source: executing DeleteByFilter for hash %s",
         hash.c_str());
    std::string filter = "hash = '" + escape_filter_literal(hash) + "'";
    ZvecStatus status =
        zvec_delete_by_filter(g_state.collection, filter.c_str());
    if (status != ZVEC_OK) {
      LOGE("edgemind_delete_source: zvec_delete_by_filter failed");
    }
    zvec_flush(g_state.collection);
    remove_source_index(hash);
  }

  return {1, 0, nullptr};
}

FfiStringResult edgemind_embed_text(const char *embedding_path,
                                    const char *text, int32_t is_query) {
  FfiStringResult res = {1, 0, nullptr};

  if (!text || std::strlen(text) == 0) {
    res.success = 0;
    res.value = allocate_string("text is required");
    return res;
  }

  MNNR_Embedding embedding_handle = nullptr;
  int32_t dim = 0;
  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    const std::string override_path = embedding_path ? embedding_path : "";
    const std::string *path_ptr = override_path.empty() ? nullptr : &override_path;
    if (!ensure_embedding_engine_loaded_locked(path_ptr) ||
        !g_state.embedding_engine) {
      res.success = 0;
      res.value = allocate_string("Embedding engine not initialized");
      return res;
    }
    embedding_handle = g_state.embedding_engine;
    dim = resolve_embedding_dim();
  }

  std::string input = text;
  if (is_query == 1) {
    input = prepare_query_for_embedding(input);
  }

  std::vector<float> vector(dim);
  const size_t generated =
      mnnr_embedding_generate(embedding_handle, input.c_str(), vector.data(),
                              static_cast<size_t>(dim));
  if (generated == 0) {
    res.success = 0;
    res.value = allocate_string("Failed to generate embedding");
    return res;
  }

  rapidjson::StringBuffer buffer;
  rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
  writer.StartArray();
  for (int32_t i = 0; i < dim; ++i) {
    writer.Double(static_cast<double>(vector[i]));
  }
  writer.EndArray();
  res.value = allocate_string(buffer.GetString());
  return res;
}

FfiStringResult edgemind_search_knowledge(const char *query, int32_t limit) {
  MNNR_Embedding embedding_handle = nullptr;
  ZvecCollection collection_handle = nullptr;
  int32_t dim = 0;

  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    FfiStringResult res = {1, 0, allocate_string("[]")};

    if (!query || std::strlen(query) == 0)
      return res;
    if (limit <= 0)
      limit = 5;

    if (!ensure_rag_engines_loaded() || !g_state.collection ||
        !g_state.embedding_engine)
      return res;

    embedding_handle = g_state.embedding_engine;
    collection_handle = g_state.collection;
    dim = resolve_embedding_dim();
  }

  // Execute embedding and search WITHOUT global lock
  FfiStringResult res = {1, 0, allocate_string("[]")};
  std::string json = execute_search_json(query, limit, nullptr,
                                         embedding_handle, collection_handle,
                                         dim);
  edgemind_free_string(res.value);
  res.value = allocate_string(json);

  return res;
}

FfiStringResult edgemind_search_in_document(const char *doc_id,
                                            const char *query, int32_t limit) {
  MNNR_Embedding embedding_handle = nullptr;
  ZvecCollection collection_handle = nullptr;
  int32_t dim = 0;

  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    FfiStringResult res = {1, 0, allocate_string("[]")};

    if (!doc_id || std::strlen(doc_id) == 0 || !query ||
        std::strlen(query) == 0)
      return res;
    if (limit <= 0)
      limit = 5;

    if (!ensure_rag_engines_loaded() || !g_state.collection ||
        !g_state.embedding_engine)
      return res;

    embedding_handle = g_state.embedding_engine;
    collection_handle = g_state.collection;
    dim = resolve_embedding_dim();
  }

  // Execute embedding and search WITHOUT global lock
  FfiStringResult res = {1, 0, allocate_string("[]")};
  std::string filter = "hash = '" + escape_filter_literal(doc_id) + "'";
  std::string json = execute_search_json(query, limit, filter.c_str(),
                                         embedding_handle, collection_handle,
                                         dim);
  edgemind_free_string(res.value);
  res.value = allocate_string(json);

  return res;
}

FfiStringResult edgemind_add_paged_document(const char *pages_json,
                                            const char *metadata_json) {
  if (!pages_json || !metadata_json) {
    return {0, 0, allocate_string("Missing input")};
  }

  rapidjson::Document pages_doc;
  if (pages_doc.Parse(pages_json).HasParseError() || !pages_doc.IsArray()) {
    return {0, 0, allocate_string("Invalid pages format")};
  }

  struct PageTask {
    int index;
    std::string content;
    std::string chunk_id;
  };
  std::vector<PageTask> tasks;
  tasks.reserve(pages_doc.Size());
  for (rapidjson::SizeType i = 0; i < pages_doc.Size(); i++) {
    auto &page = pages_doc[i];
    if (!page.IsObject() || !page.HasMember("text") ||
        !page["text"].IsString()) {
      continue;
    }
    std::string content = page["text"].GetString();
    if (content.empty()) {
      continue;
    }
    tasks.push_back({(int)i, std::move(content), ""});
  }

  std::string meta_str(metadata_json);
  std::string hash = get_json_string_value(meta_str, "hash");
  if (hash.empty()) {
    auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                      std::chrono::system_clock::now().time_since_epoch())
                      .count();
    hash =
        "doc_" + std::to_string(now_ms) + "_" + std::to_string(rand() % 10000);
  }
  std::string metadata_with_hash = ensure_metadata_hash(meta_str, hash);
  for (auto &t : tasks) {
    t.chunk_id = chunk_id_for_hash(hash, t.index);
  }

  MNNR_Embedding embedding_handle = nullptr;
  ZvecCollection coll_handle = nullptr;
  int32_t dim = 0;

  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    if (!ensure_rag_engines_loaded() || !g_state.collection ||
        !g_state.embedding_engine) {
      return {0, 0, allocate_string("Engines not initialized or load failed")};
    }
    embedding_handle = g_state.embedding_engine;
    coll_handle = g_state.collection;
    dim = resolve_embedding_dim();

    if (g_state.deleted_hashes.erase(hash) > 0) {
      save_deleted_hashes();
      LOGI("edgemind_add_paged_document: un-deleted hash '%s'", hash.c_str());
    }
  }

  int total_pages = pages_doc.Size();
  if (total_pages == 0) {
    return {1, 0, allocate_string(hash)};
  }

  LOGI("edgemind_add_paged_document: importing %d pages, hash='%s'",
       total_pages, hash.c_str());

  int success_count = 0;
  struct EmbeddedPage {
    int index;
    std::string chunk_id;
    std::string content;
    std::vector<float> vector;
    bool ok;
  };
  auto embed_page = [&](PageTask task) -> EmbeddedPage {
    EmbeddedPage out{task.index, std::move(task.chunk_id),
                     std::move(task.content), std::vector<float>((size_t)dim),
                     false};
    size_t gen_res = mnnr_embedding_generate(
        embedding_handle, out.content.c_str(), out.vector.data(), dim);
    out.ok = (gen_res > 0);
    return out;
  };

  auto insert_page = [&](EmbeddedPage &ready) {
    if (!ready.ok) {
      LOGE("edgemind_add_paged_document: embedding failed for page %d",
           ready.index);
      return;
    }
    ZvecStatus st =
        zvec_insert(coll_handle, ready.chunk_id.c_str(), ready.vector.data(),
                    (uint32_t)dim, ready.content.c_str(),
                    metadata_with_hash.c_str(), hash.c_str());
    if (st == ZVEC_OK) {
      success_count++;
    } else {
      LOGE("edgemind_add_paged_document: zvec_insert failed for chunk %s "
           "(status=%d)",
           ready.chunk_id.c_str(), st);
    }
  };

  // Pipeline: embed next page while inserting current one
  std::future<EmbeddedPage> in_flight;
  bool has_in_flight = false;
  for (size_t i = 0; i < tasks.size(); ++i) {
    if (!has_in_flight) {
      in_flight =
          std::async(std::launch::async, embed_page, std::move(tasks[i]));
      has_in_flight = true;
      continue;
    }

    EmbeddedPage ready = in_flight.get();
    has_in_flight = false;

    // Launch next embedding immediately before blocking on insert
    in_flight = std::async(std::launch::async, embed_page, std::move(tasks[i]));
    has_in_flight = true;

    insert_page(ready);
  }

  if (has_in_flight) {
    EmbeddedPage ready = in_flight.get();
    insert_page(ready);
  }

  // Flush once after all pages are inserted for efficiency
  if (coll_handle) {
    zvec_flush(coll_handle);
  }

  LOGI("edgemind_add_paged_document: completed - indexed %d/%d pages for hash "
       "'%s'",
       success_count, total_pages, hash.c_str());
  if (success_count > 0) {
    upsert_source_index(hash, metadata_with_hash);
  }

  return {1, 0, allocate_string(hash)};
}

FfiStringResult edgemind_add_documents_bulk(const char *documents_json) {
  if (!documents_json) {
    return {0, 0, allocate_string("Missing input")};
  }

  rapidjson::Document docs_doc;
  if (docs_doc.Parse(documents_json).HasParseError() || !docs_doc.IsArray()) {
    return {0, 0, allocate_string("Invalid documents format")};
  }

  MNNR_Embedding embedding_handle = nullptr;
  ZvecCollection coll_handle = nullptr;
  int32_t dim = 0;

  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    if (!ensure_rag_engines_loaded() || !g_state.collection ||
        !g_state.embedding_engine) {
      return {0, 0, allocate_string("Engines not initialized or load failed")};
    }
    embedding_handle = g_state.embedding_engine;
    coll_handle = g_state.collection;
    dim = resolve_embedding_dim();
  }

  std::vector<float> vector((size_t)dim);
  int inserted_count = 0;
  int attempted_count = 0;

  for (auto &doc : docs_doc.GetArray()) {
    if (!doc.IsObject()) {
      continue;
    }
    if (!doc.HasMember("content") || !doc["content"].IsString()) {
      continue;
    }

    const std::string content = doc["content"].GetString();
    if (content.empty()) {
      continue;
    }

    std::string metadata_json = "{}";
    if (doc.HasMember("metadata")) {
      if (doc["metadata"].IsString()) {
        metadata_json = doc["metadata"].GetString();
      } else if (doc["metadata"].IsObject()) {
        metadata_json = json_value_to_string(doc["metadata"]);
      }
    }

    std::string hash = get_json_string_value(metadata_json, "hash");
    if (hash.empty()) {
      hash = get_json_string_value(metadata_json, "id");
    }
    if (hash.empty()) {
      auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::system_clock::now().time_since_epoch())
                        .count();
      hash = "doc_" + std::to_string(now_ms) + "_" +
             std::to_string(rand() % 10000);
    }

    std::string metadata_with_hash = ensure_metadata_hash(metadata_json, hash);
    const std::string chunk_id = chunk_id_for_hash(hash, 0);

    attempted_count++;
    size_t gen_res = mnnr_embedding_generate(
        embedding_handle, content.c_str(), vector.data(), dim);
    if (gen_res == 0) {
      LOGE("edgemind_add_documents_bulk: embedding failed for hash %s",
           hash.c_str());
      continue;
    }

    ZvecStatus st = zvec_insert(coll_handle, chunk_id.c_str(), vector.data(),
                                (uint32_t)dim, content.c_str(),
                                metadata_with_hash.c_str(), hash.c_str());
    if (st != ZVEC_OK) {
      LOGE("edgemind_add_documents_bulk: zvec_insert failed for hash %s (status=%d)",
           hash.c_str(), st);
      continue;
    }

    inserted_count++;
    upsert_source_index(hash, metadata_with_hash);
  }

  if (coll_handle && inserted_count > 0) {
    zvec_flush(coll_handle);
  }

  LOGI("edgemind_add_documents_bulk: completed - indexed %d/%d documents",
       inserted_count, attempted_count);
  return {1, 0, allocate_string(std::to_string(inserted_count))};
}

FfiResult edgemind_rebuild_sources_index() {
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
  if (!ensure_rag_engines_loaded() || !g_state.collection) {
    return {0, -1, allocate_string("Not initialized")};
  }

  clear_source_index();
  uint64_t total_docs = 0;
  zvec_count(g_state.collection, &total_docs);
  if (total_docs == 0) {
    return {1, 0, nullptr};
  }

  int32_t dim = resolve_embedding_dim();
  ZvecSearchResult *results = nullptr;
  uint32_t count = 0;
  ZvecStatus status =
      zvec_list_sources(g_state.collection, (uint32_t)dim, &results, &count);
  if (status != ZVEC_OK) {
    return {0, -1, allocate_string("Failed to scan collection")};
  }

  int rebuilt = 0;
  std::unordered_set<std::string> seen_hashes;
  for (uint32_t i = 0; i < count; ++i) {
    std::string metadata = results[i].metadata ? results[i].metadata : "{}";
    std::string hash = get_json_string_value(metadata, "hash");
    if (hash.empty() && results[i].id) {
      hash = std::string(results[i].id);
      metadata = ensure_metadata_hash(metadata, hash);
    }
    if (hash.empty() || seen_hashes.find(hash) != seen_hashes.end()) {
      continue;
    }
    seen_hashes.insert(hash);
    upsert_source_index(hash, metadata);
    rebuilt++;
  }

  if (results) {
    zvec_free_results(results, count);
  }
  return {1, rebuilt, nullptr};
}

// =============================================================================
// Audio Transcription
// =============================================================================

#if defined(EDGEMIND_SHERPA_MNN_ASR_AVAILABLE)
static bool ensure_asr_loaded() {
  if (g_state.asr_recognizer) return true;
  if (g_state.whisper_dir.empty()) {
    LOGE("ASR model directory not configured");
    return false;
  }

  LOGI("Loading ASR model from: %s", g_state.whisper_dir.c_str());

  std::string backend_name;
  std::string load_error;
  auto recognizer = edgemind::createAsrRecognizer(
      g_state.whisper_dir, backend_name, load_error,
      g_state.asr_rnnoise_enabled);
  if (!recognizer) {
    LOGE("Failed to load ASR model: %s", load_error.c_str());
    return false;
  }

  g_state.asr_recognizer = std::move(recognizer);
  LOGI("ASR model loaded successfully (%s)", backend_name.c_str());
  return true;
}

static void emit_asr_stream_callback(StreamCallback callback, void *user_data,
                                     const std::string &text,
                                     int32_t is_final) {
  if (!callback) {
    return;
  }

  callback(reinterpret_cast<const char *>(allocate_string(text)), is_final,
           user_data);
}
#endif

FfiResult edgemind_init_whisper(const char *model_dir) {
  if (!model_dir || std::strlen(model_dir) == 0) {
    return {0, -1, allocate_string("model_dir is required")};
  }
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
  g_state.asr_recognizer.reset();
  g_state.whisper_dir = model_dir;
#if defined(EDGEMIND_SHERPA_MNN_ASR_AVAILABLE)
  if (ensure_asr_loaded()) {
    return {1, 0, nullptr};
  }
  return {0, -2, allocate_string("Failed to load ASR model")};
#else
  return {0, -1, allocate_string("ASR not compiled in this build")};
#endif
}

FfiResult edgemind_set_asr_rnnoise_enabled(int32_t enabled) {
#if defined(EDGEMIND_SHERPA_MNN_ASR_AVAILABLE)
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
  g_state.asr_rnnoise_enabled = enabled != 0;
  g_state.asr_recognizer.reset();
  return {1, 0, nullptr};
#else
  return {0, -1, allocate_string("ASR not compiled in this build")};
#endif
}

FfiStringResult edgemind_transcribe_audio(const char *audio_path) {
  if (!audio_path || std::strlen(audio_path) == 0) {
    return {0, 0, allocate_string("audio_path is required")};
  }

#if defined(EDGEMIND_SHERPA_MNN_ASR_AVAILABLE)
  if (!ensure_asr_loaded()) {
    return {0, -1, allocate_string("ASR model not available. "
        "Place a supported ASR model bundle in the model directory.")};
  }

  LOGI("Transcribing audio: %s", audio_path);
  std::string text;
  std::string transcribe_error;
  {
    std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
    if (!g_state.asr_recognizer->transcribeFile(audio_path, text,
                                                transcribe_error)) {
      return {0, -2, allocate_string(transcribe_error)};
    }
  }

  // Build JSON response
  rapidjson::StringBuffer sb;
  rapidjson::Writer<rapidjson::StringBuffer> w(sb);
  w.StartObject();
  w.Key("text");
  w.String(text.c_str(), text.size());
  w.EndObject();

  LOGI("Transcription result: %s", text.c_str());
  return {1, 0, allocate_string(sb.GetString())};
#else
  LOGI("edgemind_transcribe_audio: ASR not compiled in");
  return {0, -1, allocate_string("ASR transcription not compiled in this build")};
#endif
}

FfiResult edgemind_transcribe_audio_stream(const char *audio_path,
                                           StreamCallback callback,
                                           void *user_data) {
  if (!audio_path || std::strlen(audio_path) == 0) {
    return {0, -1, allocate_string("audio_path is required")};
  }
  if (!callback) {
    return {0, -1, allocate_string("callback is required")};
  }

#if defined(EDGEMIND_SHERPA_MNN_ASR_AVAILABLE)
  if (!ensure_asr_loaded()) {
    return {0, -1, allocate_string("ASR model not available. "
        "Place a supported ASR model bundle in the model directory.")};
  }

  const std::string audio_path_copy(audio_path);
  std::thread([audio_path_copy, callback, user_data]() {
    LOGI("Streaming transcription for audio: %s", audio_path_copy.c_str());
    std::string text;
    std::string transcribe_error;
    bool success = false;
    {
      std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
      success = g_state.asr_recognizer->transcribeFile(
          audio_path_copy, text, transcribe_error,
          [callback, user_data](const std::string &partial_text,
                                bool is_final) {
            emit_asr_stream_callback(callback, user_data, partial_text,
                                     is_final ? 1 : 0);
          });
    }

    if (!success) {
      emit_asr_stream_callback(callback, user_data, transcribe_error, -1);
      return;
    }

    LOGI("Streaming transcription complete: %s", text.c_str());
  }).detach();

  return {1, 0, nullptr};
#else
  LOGI("edgemind_transcribe_audio_stream: ASR not compiled in");
  return {0, -1, allocate_string("ASR transcription not compiled in this build")};
#endif
}

// =============================================================================
// Text-to-Speech (Supertonic TTS via MNN)
// =============================================================================

FfiResult edgemind_tts_init(const char *model_dir, const char *voice) {
  if (!model_dir || std::strlen(model_dir) == 0) {
    return {0, -1, allocate_string("model_dir is required")};
  }
  const char *selected_voice =
      (voice && std::strlen(voice) > 0) ? voice : "F1";
#ifdef SUPERTONIC_AVAILABLE
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
  g_state.tts_dir = model_dir;
  g_state.tts_voice = selected_voice;
  if (g_state.tts_engine) {
    delete g_state.tts_engine;
    g_state.tts_engine = nullptr;
  }
  g_state.tts_engine = new SupertonicTTS();
  int ret = g_state.tts_engine->load(model_dir, selected_voice, 4);
  if (ret != 0) {
    delete g_state.tts_engine;
    g_state.tts_engine = nullptr;
    return {0, -2, allocate_string("Failed to load Supertonic TTS model")};
  }
  LOGI("Supertonic TTS engine loaded from %s with voice %s", model_dir,
       selected_voice);
  return {1, 0, nullptr};
#else
  return {0, -1, allocate_string("TTS not compiled (SUPERTONIC_AVAILABLE not defined)")};
#endif
}

FfiResult edgemind_tts_synthesize(const char *text, const char *output_path) {
  if (!text || std::strlen(text) == 0) {
    return {0, -1, allocate_string("text is required")};
  }
  if (!output_path || std::strlen(output_path) == 0) {
    return {0, -1, allocate_string("output_path is required")};
  }
#ifdef SUPERTONIC_AVAILABLE
  // Serialize synthesis and voice reinitialization on the shared engine.
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
  if (!g_state.tts_engine) {
    // Try to lazy-load if tts_dir was set
    if (!g_state.tts_dir.empty()) {
      FfiResult init_res =
          edgemind_tts_init(g_state.tts_dir.c_str(), g_state.tts_voice.c_str());
      if (!init_res.success) return {0, -2, init_res.error_message};
    } else {
      return {0, -2, allocate_string("TTS engine not initialized. Call edgemind_tts_init first.")};
    }
  }

  std::vector<float> pcm;
  g_state.tts_engine->synthesize(text, 1.0f, 3, pcm);

  if (pcm.empty()) {
    return {0, -3, allocate_string("TTS synthesis produced no audio")};
  }

  // Convert float32 PCM to int16
  std::vector<int16_t> pcm16(pcm.size());
  const float gain = std::clamp(g_state.tts_gain, 1.0f, 2.5f);
  for (size_t i = 0; i < pcm.size(); i++) {
    float s = pcm[i] * gain * 32767.0f;
    if (s > 32767.0f) s = 32767.0f;
    if (s < -32768.0f) s = -32768.0f;
    pcm16[i] = (int16_t)s;
  }

  // Write WAV file (44100 Hz, 16-bit, mono)
  FILE *fp = fopen(output_path, "wb");
  if (!fp) {
    return {0, -4, allocate_string("Failed to open output file for writing")};
  }

  const int32_t sample_rate = g_state.tts_engine->sampleRate();
  const int16_t num_channels = 1;
  const int16_t bits_per_sample = 16;
  const int32_t data_size = (int32_t)(pcm16.size() * sizeof(int16_t));
  const int32_t fmt_chunk_size = 16;
  const int16_t audio_format = 1; // PCM
  const int32_t byte_rate = sample_rate * num_channels * bits_per_sample / 8;
  const int16_t block_align = num_channels * bits_per_sample / 8;
  const int32_t riff_size = 36 + data_size;

  fwrite("RIFF", 1, 4, fp);
  fwrite(&riff_size, 4, 1, fp);
  fwrite("WAVE", 1, 4, fp);
  fwrite("fmt ", 1, 4, fp);
  fwrite(&fmt_chunk_size, 4, 1, fp);
  fwrite(&audio_format, 2, 1, fp);
  fwrite(&num_channels, 2, 1, fp);
  fwrite(&sample_rate, 4, 1, fp);
  fwrite(&byte_rate, 4, 1, fp);
  fwrite(&block_align, 2, 1, fp);
  fwrite(&bits_per_sample, 2, 1, fp);
  fwrite("data", 1, 4, fp);
  fwrite(&data_size, 4, 1, fp);
  fwrite(pcm16.data(), sizeof(int16_t), pcm16.size(), fp);
  fclose(fp);

  LOGI("TTS synthesized %zu samples to %s", pcm16.size(), output_path);
  return {1, 0, nullptr};
#else
  return {0, -1, allocate_string("TTS not compiled (SUPERTONIC_AVAILABLE not defined)")};
#endif
}

FfiResult edgemind_tts_set_gain(float gain) {
#ifdef SUPERTONIC_AVAILABLE
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
  g_state.tts_gain = std::clamp(gain, 1.0f, 2.5f);
  return {1, 0, nullptr};
#else
  return {0, -1, allocate_string("TTS not compiled (SUPERTONIC_AVAILABLE not defined)")};
#endif
}

int32_t edgemind_tts_is_available() {
#ifdef SUPERTONIC_AVAILABLE
  std::lock_guard<std::recursive_mutex> lock(g_state.lifecycle_mutex);
  return g_state.tts_engine != nullptr ? 1 : 0;
#else
  return 0;
#endif
}

// =============================================================================
// Conversations
// =============================================================================

FfiStringResult edgemind_list_conversations() {
  return {1, 0, allocate_string("[]")};
}

FfiStringResult edgemind_load_conversation(const char *id) {
  return {1, 0, allocate_string("{}")};
}

FfiResult edgemind_delete_conversation(const char *id) {
  return {1, 0, nullptr};
}

FfiResult edgemind_chat_binary_async(const uint8_t *request_data,
                                     size_t request_size,
                                     uint8_t **response_data,
                                     size_t *response_size) {
  (void)request_data;
  (void)request_size;
  (void)response_data;
  (void)response_size;
  return {0, -1, allocate_string("Binary protocol not enabled in this build")};
}

FfiResult edgemind_embedding_binary_async(const uint8_t *request_data,
                                          size_t request_size,
                                          uint8_t **response_data,
                                          size_t *response_size) {
  (void)request_data;
  (void)request_size;
  (void)response_data;
  (void)response_size;
  return {0, -1, allocate_string("Binary protocol not enabled in this build")};
}

void edgemind_free_binary_data(uint8_t *data) {
  if (data) {
    free(data);
  }
}
