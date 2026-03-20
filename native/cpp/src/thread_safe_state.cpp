#include "thread_safe_state.h"

// Static member definitions
thread_local std::string ThreadSafeState::tl_collection_path;
thread_local std::string ThreadSafeState::tl_model_dir;
thread_local bool ThreadSafeState::tl_initialized = false;
thread_local int32_t ThreadSafeState::tl_embedding_dim = 0;

// Global instance definition
ThreadSafeState g_thread_safe_state;