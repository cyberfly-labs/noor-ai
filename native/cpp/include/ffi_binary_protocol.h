#ifndef FFI_BINARY_PROTOCOL_H
#define FFI_BINARY_PROTOCOL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Binary Protocol for FFI Communication
// Purpose: Reduce JSON serialization overhead in Dart-C++ FFI layer
// =============================================================================

// Message types for binary protocol
enum class BinaryMessageType : uint8_t {
  CHAT_REQUEST = 1,
  CHAT_RESPONSE = 2,
  CHAT_STREAM_REQUEST = 3,
  CHAT_STREAM_CHUNK = 4,
  EMBEDDING_REQUEST = 5,
  EMBEDDING_RESPONSE = 6,
  SEARCH_REQUEST = 7,
  SEARCH_RESPONSE = 8,
  ERROR_RESPONSE = 255
};

// Binary message header
struct BinaryMessageHeader {
  uint32_t magic;           // 0xEDGEMIND (0x444547454D494E44)
  uint8_t version;          // Protocol version
  BinaryMessageType type;   // Message type
  uint32_t payload_size;    // Size of payload in bytes
  uint32_t checksum;        // Simple checksum for integrity
};

// Chat request payload (binary)
struct ChatRequestPayload {
  uint32_t message_length;
  uint32_t conversation_id_length;
  uint8_t thinking_enabled;
  uint8_t use_documents;
  uint32_t focused_doc_id_length;
  // Variable length data follows:
  // - message bytes
  // - conversation_id bytes (if length > 0)
  // - focused_doc_id bytes (if length > 0)
};

// Chat response payload (binary)
struct ChatResponsePayload {
  uint32_t response_length;
  uint32_t error_code;
  // Variable length data follows:
  // - response bytes (if no error)
  // - error message bytes (if error)
};

// Embedding request payload (binary)
struct EmbeddingRequestPayload {
  uint32_t text_length;
  uint32_t max_tokens;
  // Variable length data follows:
  // - text bytes
};

// Embedding response payload (binary)
struct EmbeddingResponsePayload {
  uint32_t embedding_length;
  uint32_t error_code;
  // Variable length data follows:
  // - embedding float array (if no error)
  // - error message bytes (if error)
};

// Constants
static const uint32_t BINARY_PROTOCOL_MAGIC = 0x444547454D494E44; // "EDGEMIND"
static const uint8_t BINARY_PROTOCOL_VERSION = 1;
static const size_t BINARY_HEADER_SIZE = sizeof(BinaryMessageHeader);

// =============================================================================
// Utility Functions
// =============================================================================

// Calculate simple checksum for payload
static inline uint32_t binary_checksum(const uint8_t* data, size_t size) {
  uint32_t checksum = 0;
  for (size_t i = 0; i < size; i++) {
    checksum += data[i];
    checksum = (checksum << 1) | (checksum >> 31); // Rotate left
  }
  return checksum;
}

// Validate message header
static inline int binary_validate_header(const BinaryMessageHeader* header) {
  if (header->magic != BINARY_PROTOCOL_MAGIC) return 0;
  if (header->version != BINARY_PROTOCOL_VERSION) return 0;
  if (header->payload_size > 16 * 1024 * 1024) return 0; // Max 16MB
  return 1;
}

// =============================================================================
// Async API Functions (to be implemented)
// =============================================================================

// Asynchronous chat request with binary protocol
EDGEMIND_EXPORT FfiResult edgemind_chat_binary_async(
  const uint8_t* request_data,
  size_t request_size,
  uint8_t** response_data,
  size_t* response_size
);

// Asynchronous embedding request with binary protocol
EDGEMIND_EXPORT FfiResult edgemind_embedding_binary_async(
  const uint8_t* request_data,
  size_t request_size,
  uint8_t** response_data,
  size_t* response_size
);

// Free binary response data
EDGEMIND_EXPORT void edgemind_free_binary_data(uint8_t* data);

#ifdef __cplusplus
}
#endif

#endif // FFI_BINARY_PROTOCOL_H