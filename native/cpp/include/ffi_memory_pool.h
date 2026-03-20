#ifndef FFI_MEMORY_POOL_H
#define FFI_MEMORY_POOL_H

#include <vector>
#include <memory>
#include <mutex>
#include <unordered_map>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Memory Pool for FFI Performance Optimization
// Purpose: Reduce memory allocation overhead in Dart-C++ FFI layer
// =============================================================================

class FFIMemoryPool {
private:
  // Thread-local storage for buffers
  thread_local static std::vector<uint8_t> tl_request_buffer;
  thread_local static std::vector<uint8_t> tl_response_buffer;
  thread_local static std::vector<float> tl_embedding_buffer;
  
  // Global pool for larger allocations
  static std::mutex pool_mutex;
  static std::unordered_map<size_t, std::vector<std::vector<uint8_t>>> buffer_pools;
  
public:
  // Get a request buffer (thread-local, grows as needed)
  static std::vector<uint8_t>& get_request_buffer(size_t min_size = 4096) {
    if (tl_request_buffer.capacity() < min_size) {
      tl_request_buffer.reserve(min_size * 2); // Double capacity
    }
    tl_request_buffer.clear();
    return tl_request_buffer;
  }
  
  // Get a response buffer (thread-local, grows as needed)
  static std::vector<uint8_t>& get_response_buffer(size_t min_size = 4096) {
    if (tl_response_buffer.capacity() < min_size) {
      tl_response_buffer.reserve(min_size * 2); // Double capacity
    }
    tl_response_buffer.clear();
    return tl_response_buffer;
  }
  
  // Get an embedding buffer (thread-local, grows as needed)
  static std::vector<float>& get_embedding_buffer(size_t min_size = 768) {
    if (tl_embedding_buffer.capacity() < min_size) {
      tl_embedding_buffer.reserve(min_size * 2); // Double capacity
    }
    tl_embedding_buffer.clear();
    return tl_embedding_buffer;
  }
  
  // Get a pooled buffer (for larger allocations)
  static std::vector<uint8_t> get_pooled_buffer(size_t size) {
    std::lock_guard<std::mutex> lock(pool_mutex);
    
    auto& pool = buffer_pools[size];
    if (!pool.empty()) {
      std::vector<uint8_t> buffer = std::move(pool.back());
      pool.pop_back();
      return buffer;
    }
    
    return std::vector<uint8_t>(size);
  }
  
  // Return a buffer to the pool
  static void return_pooled_buffer(std::vector<uint8_t> buffer) {
    if (buffer.empty()) return;
    
    std::lock_guard<std::mutex> lock(pool_mutex);
    size_t size = buffer.size();
    
    // Only pool buffers of reasonable size (1KB to 1MB)
    if (size >= 1024 && size <= 1024 * 1024) {
      buffer.clear(); // Clear but keep capacity
      buffer_pools[size].push_back(std::move(buffer));
      
      // Limit pool size to prevent memory bloat
      if (buffer_pools[size].size() > 10) {
        buffer_pools[size].erase(buffer_pools[size].begin());
      }
    }
  }
  
  // Pre-allocate common buffer sizes
  static void preallocate_buffers() {
    // Pre-allocate thread-local buffers
    get_request_buffer(16384);  // 16KB
    get_response_buffer(16384); // 16KB
    get_embedding_buffer(1536); // 1536 floats (common embedding size)
    
    // Pre-allocate some pooled buffers
    std::vector<size_t> common_sizes = {
      1024,   // 1KB
      4096,   // 4KB
      8192,   // 8KB
      16384,  // 16KB
      32768,  // 32KB
      65536   // 64KB
    };
    
    for (size_t size : common_sizes) {
      for (int i = 0; i < 3; i++) { // 3 buffers of each size
        return_pooled_buffer(std::vector<uint8_t>(size));
      }
    }
  }
  
  // Clear all pools (call during shutdown)
  static void clear_pools() {
    std::lock_guard<std::mutex> lock(pool_mutex);
    buffer_pools.clear();
  }
};

// Static member definitions
thread_local std::vector<uint8_t> FFIMemoryPool::tl_request_buffer;
thread_local std::vector<uint8_t> FFIMemoryPool::tl_response_buffer;
thread_local std::vector<float> FFIMemoryPool::tl_embedding_buffer;
std::mutex FFIMemoryPool::pool_mutex;
std::unordered_map<size_t, std::vector<std::vector<uint8_t>>> FFIMemoryPool::buffer_pools;

// C API wrapper for memory pool
extern "C" {
  
  // Initialize memory pool
  void ffi_memory_pool_init() {
    FFIMemoryPool::preallocate_buffers();
  }
  
  // Cleanup memory pool
  void ffi_memory_pool_cleanup() {
    FFIMemoryPool::clear_pools();
  }
  
  // Get a request buffer
  uint8_t* ffi_get_request_buffer(size_t min_size, size_t* actual_size) {
    auto& buffer = FFIMemoryPool::get_request_buffer(min_size);
    *actual_size = buffer.capacity();
    return buffer.data();
  }
  
  // Get a response buffer
  uint8_t* ffi_get_response_buffer(size_t min_size, size_t* actual_size) {
    auto& buffer = FFIMemoryPool::get_response_buffer(min_size);
    *actual_size = buffer.capacity();
    return buffer.data();
  }
  
  // Get an embedding buffer
  float* ffi_get_embedding_buffer(size_t min_size, size_t* actual_size) {
    auto& buffer = FFIMemoryPool::get_embedding_buffer(min_size);
    *actual_size = buffer.capacity();
    return buffer.data();
  }
  
  // Get a pooled buffer
  uint8_t* ffi_get_pooled_buffer(size_t size) {
    auto buffer = FFIMemoryPool::get_pooled_buffer(size);
    uint8_t* data = new uint8_t[size];
    std::copy(buffer.begin(), buffer.end(), data);
    return data;
  }
  
  // Return a pooled buffer
  void ffi_return_pooled_buffer(uint8_t* buffer, size_t size) {
    if (buffer) {
      std::vector<uint8_t> vec(buffer, buffer + size);
      FFIMemoryPool::return_pooled_buffer(std::move(vec));
      delete[] buffer;
    }
  }
  
} // extern "C"

#endif // __cplusplus

#endif // FFI_MEMORY_POOL_H