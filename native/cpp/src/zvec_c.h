// Copyright 2026 EdgeMind
// C wrapper for Alibaba zvec - exposes C++ API to Rust FFI
//
// This is a thin C-compatible wrapper over zvec::Collection

#ifndef ZVEC_C_H
#define ZVEC_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// TYPES
// ============================================================================

/// Opaque handle to a zvec collection
typedef void *ZvecCollection;

/// Status codes
typedef enum {
  ZVEC_OK = 0,
  ZVEC_ERROR_INVALID_PARAM = -1,
  ZVEC_ERROR_NOT_FOUND = -2,
  ZVEC_ERROR_IO = -3,
  ZVEC_ERROR_INTERNAL = -4,
  ZVEC_ERROR_ALREADY_EXISTS = -5,
  ZVEC_ERROR_NOT_SUPPORTED = -6,
} ZvecStatus;

/// Search result structure
typedef struct {
  char *id;       // Document ID (caller must free with zvec_free_string)
  float score;    // Similarity score (0-1, higher is better)
  char *metadata; // JSON metadata (caller must free)
  char *content;  // Document content text (caller must free)
} ZvecSearchResult;

// ============================================================================
// COLLECTION LIFECYCLE
// ============================================================================

/**
 * Create and open a new zvec collection.
 *
 * @param path       Path to store the collection (directory will be created)
 * @param name       Collection name
 * @param dimension  Vector dimension (e.g., 384 for MiniLM)
 * @param out        Output: collection handle
 * @return ZVEC_OK on success, error code otherwise
 */
ZvecStatus zvec_create_collection(const char *path, const char *name,
                                  uint32_t dimension, ZvecCollection *out);

/**
 * Open an existing zvec collection.
 *
 * @param path  Path to the collection
 * @param out   Output: collection handle
 * @return ZVEC_OK on success, error code otherwise
 */
ZvecStatus zvec_open_collection(const char *path, ZvecCollection *out);

/**
 * Close and release a collection.
 *
 * @param coll  Collection handle (may be NULL)
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_close_collection(ZvecCollection coll);

/**
 * Flush pending writes to disk.
 *
 * @param coll  Collection handle
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_flush(ZvecCollection coll);

/**
 * Optimize the collection by merging buffered vectors into the HNSW index.
 * Call after inserting a batch of documents to improve search performance.
 *
 * @param coll  Collection handle
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_optimize(ZvecCollection coll);

/**
 * Check if a field exists in the collection schema.
 *
 * @param coll   Collection handle
 * @param field  Field name to check
 * @return 1 if field exists, 0 if not or invalid handle
 */
int zvec_has_field(ZvecCollection coll, const char *field);

/**
 * Destroy a collection (delete all data).
 *
 * @param coll  Collection handle (will be invalidated)
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_destroy(ZvecCollection coll);

// ============================================================================
// DOCUMENT OPERATIONS
// ============================================================================

/**
 * Insert a document with vector embedding.
 *
 * @param coll           Collection handle
 * @param id             Unique document ID (null-terminated string)
 * @param vector         Vector data (f32 array)
 * @param dimension      Vector dimension (must match collection)
 * @param content        Document content/text (null-terminated, may be NULL)
 * @param metadata_json  Additional metadata as JSON (may be NULL)
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_insert(ZvecCollection coll, const char *id, const float *vector,
                       uint32_t dimension, const char *content,
                       const char *metadata_json, const char *hash);

/**
 * Insert a batch of documents with vector embeddings.
 *
 * @param coll           Collection handle
 * @param ids            Array of document IDs
 * @param vectors        Contiguous block of vector data (count * dimension)
 * @param dimension      Vector dimension per document
 * @param count          Number of documents to insert
 * @return ZVEC_OK on success, error code otherwise
 */
ZvecStatus zvec_insert_batch(ZvecCollection coll, const char **ids,
                             const float *vectors, const char **hashes,
                             uint32_t dimension, uint32_t count);

/**
 * Delete a document by ID.
 *
 * @param coll  Collection handle
 * @param id    Document ID to delete
 * @return ZVEC_OK on success, ZVEC_ERROR_NOT_FOUND if not exists
 */
ZvecStatus zvec_delete(ZvecCollection coll, const char *id);

/**
 * Delete all documents matching a filter expression.
 *
 * @param coll       Collection handle
 * @param filter     Expression (e.g., "metadata.hash == '123'")
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_delete_by_filter(ZvecCollection coll, const char *filter);

/**
 * Fetch documents exactly by their IDs.
 *
 * @param coll        Collection handle
 * @param ids         Array of document IDs to fetch
 * @param count       Number of IDs
 * @param results     Output: array of results (caller must free with
 * zvec_free_results)
 * @param out_count   Output: actual number of results returned (some might be
 * missing)
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_fetch(ZvecCollection coll, const char **ids, uint32_t count,
                      ZvecSearchResult **results, uint32_t *out_count);

// ============================================================================
// SEARCH
// ============================================================================

/**
 * Search for similar vectors.
 *
 * @param coll        Collection handle
 * @param query       Query vector (f32 array)
 * @param dimension   Query dimension (must match collection)
 * @param topk        Number of results to return
 * @param results     Output: array of results (caller must free with
 * zvec_free_results)
 * @param out_count   Output: actual number of results returned
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_search(ZvecCollection coll, const float *query,
                       uint32_t dimension, uint32_t topk, const char *filter,
                       ZvecSearchResult **results, uint32_t *out_count);

/**
 * Search with minimum score threshold.
 *
 * @param coll           Collection handle
 * @param query          Query vector
 * @param dimension      Query dimension
 * @param topk           Max results
 * @param min_score      Minimum similarity score (0-1)
 * @param results        Output: results array
 * @param out_count      Output: result count
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_search_with_threshold(ZvecCollection coll, const float *query,
                                      uint32_t dimension, uint32_t topk,
                                      float min_score, const char *filter,
                                      ZvecSearchResult **results,
                                      uint32_t *out_count);

/**
 * List all sources.
 *
 * @param coll        Collection handle
 * @param dimension   Dimension of the vector
 * @param results     Output: results array
 * @param out_count   Output: result count
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_list_sources(ZvecCollection coll, uint32_t dimension,
                             ZvecSearchResult **results, uint32_t *out_count);

// ============================================================================
// STATS
// ============================================================================

/**
 * Get document count in collection.
 *
 * @param coll       Collection handle
 * @param out_count  Output: document count
 * @return ZVEC_OK on success
 */
ZvecStatus zvec_count(ZvecCollection coll, uint64_t *out_count);

/**
 * Get the vector dimension of the collection.
 *
 * @param coll  Collection handle
 * @return Dimension (e.g. 384) or 0 on error
 */
uint32_t zvec_get_dimension(ZvecCollection coll);

// ============================================================================
// MEMORY MANAGEMENT
// ============================================================================

/**
 * Free a string allocated by zvec.
 */
void zvec_free_string(char *str);

/**
 * Free search results array.
 *
 * @param results  Results array from zvec_search
 * @param count    Number of results
 */
void zvec_free_results(ZvecSearchResult *results, uint32_t count);

// ============================================================================
// ERROR HANDLING
// ============================================================================

/**
 * Get the last error message (thread-local).
 *
 * @return Error message string (do not free, valid until next zvec call)
 */
const char *zvec_get_last_error(void);

#ifdef __cplusplus
}
#endif

#endif // ZVEC_C_H
