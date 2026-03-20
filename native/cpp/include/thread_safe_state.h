#ifndef THREAD_SAFE_STATE_H
#define THREAD_SAFE_STATE_H

#include <memory>
#include <mutex>
#include <shared_mutex>
#include <atomic>
#include <vector>
#include <unordered_map>
#include <string>

// Forward declarations
typedef void* MNNR_LLM;
typedef void* MNNR_Embedding;
typedef void* ZvecCollection;

// =============================================================================
// Thread-Safe State Management for EdgeMind Core
// Purpose: Reduce lock contention and improve concurrent access performance
// =============================================================================

class ThreadSafeState {
private:
  // Read-mostly data (use shared_mutex for reader-writer lock)
  mutable std::shared_mutex rw_mutex;
  std::string collection_path;
  std::string model_dir;
  std::string embedding_path;
  int32_t cached_embedding_dim = 0;
  bool engines_loaded = false;
  
  // Engine handles (protected by mutex)
  MNNR_LLM llm = nullptr;
  MNNR_Embedding embedding_engine = nullptr;
  ZvecCollection collection = nullptr;
  
  // Embedding cache (thread-safe by design)
  std::unordered_map<std::string, std::vector<float>> embedding_cache;
  mutable std::mutex cache_mutex;
  
  // Atomic flags for fast checks
  std::atomic<bool> initialized{false};
  std::atomic<bool> deleted_hashes_loaded{false};
  
  // Thread-local cache for frequently accessed data
  thread_local static std::string tl_collection_path;
  thread_local static std::string tl_model_dir;
  thread_local static bool tl_initialized;
  thread_local static int32_t tl_embedding_dim;
  
public:
  ThreadSafeState() = default;
  ~ThreadSafeState() = default;
  
  // Fast read operations (no locking for atomic data)
  bool is_initialized() const {
    return initialized.load(std::memory_order_acquire);
  }
  
  bool are_hashes_loaded() const {
    return deleted_hashes_loaded.load(std::memory_order_acquire);
  }
  
  // Read operations with shared lock (multiple readers allowed)
  std::string get_collection_path() const {
    // Use thread-local cache if available
    if (!tl_collection_path.empty() && tl_initialized) {
      return tl_collection_path;
    }
    
    std::shared_lock<std::shared_mutex> lock(rw_mutex);
    return collection_path;
  }
  
  std::string get_model_dir() const {
    // Use thread-local cache if available
    if (!tl_model_dir.empty() && tl_initialized) {
      return tl_model_dir;
    }
    
    std::shared_lock<std::shared_mutex> lock(rw_mutex);
    return model_dir;
  }
  
  std::string get_embedding_path() const {
    std::shared_lock<std::shared_mutex> lock(rw_mutex);
    return embedding_path;
  }
  
  int32_t get_embedding_dim() const {
    // Use thread-local cache if available
    if (tl_initialized && tl_embedding_dim > 0) {
      return tl_embedding_dim;
    }
    
    std::shared_lock<std::shared_mutex> lock(rw_mutex);
    return cached_embedding_dim;
  }
  
  bool are_engines_loaded() const {
    std::shared_lock<std::shared_mutex> lock(rw_mutex);
    return engines_loaded;
  }
  
  // Engine access with shared lock (fast path for read-only access)
  std::tuple<MNNR_LLM, MNNR_Embedding, ZvecCollection> get_engines() const {
    std::shared_lock<std::shared_mutex> lock(rw_mutex);
    return {llm, embedding_engine, collection};
  }
  
  // Write operations with exclusive lock
  void set_paths(const std::string& coll_path, const std::string& mdl_dir, const std::string& emb_path) {
    std::unique_lock<std::shared_mutex> lock(rw_mutex);
    collection_path = coll_path;
    model_dir = mdl_dir;
    embedding_path = emb_path;
    
    // Update thread-local cache
    tl_collection_path = coll_path;
    tl_model_dir = mdl_dir;
  }
  
  void set_embedding_dim(int32_t dim) {
    std::unique_lock<std::shared_mutex> lock(rw_mutex);
    cached_embedding_dim = dim;
    tl_embedding_dim = dim;
  }
  
  void set_engines(MNNR_LLM l, MNNR_Embedding emb, ZvecCollection coll) {
    std::unique_lock<std::shared_mutex> lock(rw_mutex);
    llm = l;
    embedding_engine = emb;
    collection = coll;
    engines_loaded = (l != nullptr && emb != nullptr && coll != nullptr);
  }
  
  void set_initialized(bool init) {
    initialized.store(init, std::memory_order_release);
    tl_initialized = init;
  }
  
  void set_hashes_loaded(bool loaded) {
    deleted_hashes_loaded.store(loaded, std::memory_order_release);
  }
  
  // Cache operations (separate mutex for cache)
  bool get_cached_embedding(const std::string& key, std::vector<float>& out) const {
    std::lock_guard<std::mutex> lock(cache_mutex);
    auto it = embedding_cache.find(key);
    if (it != embedding_cache.end()) {
      out = it->second;
      return true;
    }
    return false;
  }
  
  void set_cached_embedding(const std::string& key, const std::vector<float>& embedding) {
    std::lock_guard<std::mutex> lock(cache_mutex);
    embedding_cache[key] = embedding;
    
    // Limit cache size to prevent memory bloat
    if (embedding_cache.size() > 1000) {
      // Remove oldest entries (simple FIFO)
      auto it = embedding_cache.begin();
      embedding_cache.erase(it);
    }
  }
  
  void clear_embedding_cache() {
    std::lock_guard<std::mutex> lock(cache_mutex);
    embedding_cache.clear();
  }
  
  // Fast engine access without locks (for performance-critical paths)
  // Caller must ensure engines are valid before calling this
  MNNR_LLM get_llm_fast() const {
    return llm;
  }
  
  MNNR_Embedding get_embedding_fast() const {
    return embedding_engine;
  }
  
  ZvecCollection get_collection_fast() const {
    return collection;
  }
  
  // Update thread-local cache (call after initialization)
  void update_thread_local_cache() {
    std::shared_lock<std::shared_mutex> lock(rw_mutex);
    tl_collection_path = collection_path;
    tl_model_dir = model_dir;
    tl_embedding_dim = cached_embedding_dim;
    tl_initialized = initialized.load(std::memory_order_acquire);
  }
};

// Global instance
extern ThreadSafeState g_thread_safe_state;

#endif // THREAD_SAFE_STATE_H