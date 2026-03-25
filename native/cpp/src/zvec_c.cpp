// Copyright 2026 EdgeMind
// C wrapper implementation for Alibaba zvec
// Exposes C API defined in zvec_c.h

#include "zvec_c.h"

#include <zvec/ailego/utility/float_helper.h>
#include <zvec/db/collection.h>
#include <zvec/db/doc.h>
#include <zvec/db/options.h>
#include <zvec/db/schema.h>

#include <cstdio>

#if defined(ANDROID)
#include <android/log.h>
#endif
#include <cstring>
#include <algorithm>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#if defined(ANDROID)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "ZvecC", __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "ZvecC", __VA_ARGS__)
#else
#define LOGE(...)                                                             \
  do {                                                                        \
    std::fprintf(stderr, "[ERROR] ZvecC: ");                                 \
    std::fprintf(stderr, __VA_ARGS__);                                        \
    std::fprintf(stderr, "\n");                                             \
  } while (0)
#define LOGI(...)                                                             \
  do {                                                                        \
    std::fprintf(stderr, "[INFO] ZvecC: ");                                  \
    std::fprintf(stderr, __VA_ARGS__);                                        \
    std::fprintf(stderr, "\n");                                             \
  } while (0)
#endif

// Thread-local error string
static thread_local std::string g_last_error;

static void set_error(const std::string &err) { g_last_error = err; }

const char *zvec_get_last_error(void) {
  return g_last_error.empty() ? "" : g_last_error.c_str();
}

static char *copy_string(const std::string &s) {
  char *out = (char *)malloc(s.size() + 1);
  if (!out)
    return nullptr;
  memcpy(out, s.c_str(), s.size() + 1);
  return out;
}

struct ZvecCollectionImpl {
  zvec::Collection::Ptr collection;
  std::mutex mutex; // Protect multithreaded operations
};

// Helper for collection access
static zvec::DataType
detect_vector_data_type(const zvec::Collection::Ptr &collection) {
  auto schema_res = collection->Schema();
  if (!schema_res.has_value()) {
    return zvec::DataType::VECTOR_FP16;
  }
  auto vector_fields = schema_res.value().vector_fields();
  if (vector_fields.empty()) {
    return zvec::DataType::VECTOR_FP16;
  }
  return vector_fields[0]->data_type();
}

static std::string encode_query_vector(const zvec::Collection::Ptr &collection,
                                       const float *query, uint32_t dimension) {
  zvec::DataType vector_data_type = detect_vector_data_type(collection);
  if (vector_data_type == zvec::DataType::VECTOR_FP32) {
    return std::string(reinterpret_cast<const char *>(query),
                       dimension * sizeof(float));
  }
  thread_local std::vector<uint16_t> query_f16;
  if (query_f16.size() != dimension) {
    query_f16.resize(dimension);
  }
  zvec::ailego::FloatHelper::ToFP16(query, dimension, query_f16.data());
  return std::string(reinterpret_cast<const char *>(query_f16.data()),
                     dimension * sizeof(uint16_t));
}

static ZvecStatus convert_status(const zvec::Status &status) {
  if (status.ok())
    return ZVEC_OK;
  set_error(status.message());

  switch (status.code()) {
  case zvec::StatusCode::INVALID_ARGUMENT:
    return ZVEC_ERROR_INVALID_PARAM;
  case zvec::StatusCode::NOT_FOUND:
    return ZVEC_ERROR_NOT_FOUND;
  case zvec::StatusCode::ALREADY_EXISTS:
    return ZVEC_ERROR_ALREADY_EXISTS;
  case zvec::StatusCode::NOT_SUPPORTED:
    return ZVEC_ERROR_NOT_SUPPORTED;
  default:
    return ZVEC_ERROR_INTERNAL;
  }
}

// ============================================================================
// COLLECTION LIFECYCLE
// ============================================================================

ZvecStatus zvec_create_collection(const char *path, const char *name,
                                  uint32_t dimension, ZvecCollection *out) {
  if (!path || !name || !out || dimension == 0)
    return ZVEC_ERROR_INVALID_PARAM;

  zvec::CollectionSchema schema(name);

  // Core fields: id (string), vector (vector_fp32), content (string), metadata
  // (string)
  schema.add_field(
      std::make_shared<zvec::FieldSchema>("id", zvec::DataType::STRING));
  schema.add_field(std::make_shared<zvec::FieldSchema>(
      "vector", zvec::DataType::VECTOR_FP16, dimension, false,
      std::make_shared<zvec::HnswIndexParams>(zvec::MetricType::IP)));
  schema.add_field(std::make_shared<zvec::FieldSchema>(
      "content", zvec::DataType::STRING, true));
  schema.add_field(std::make_shared<zvec::FieldSchema>(
      "metadata", zvec::DataType::STRING, true));

  // Scalar field for grouping/deletion (indexed for performance)
  schema.add_field(std::make_shared<zvec::FieldSchema>(
      "hash", zvec::DataType::STRING, true,
      std::make_shared<zvec::InvertIndexParams>()));

  zvec::CollectionOptions options{false, true};
  auto result = zvec::Collection::CreateAndOpen(path, schema, options);

  if (!result.has_value()) {
    LOGE("Failed to create collection %s: %s", name,
         result.error().message().c_str());
    return convert_status(result.error());
  }

  LOGI("Created and opened collection at %s", path);
  *out = new ZvecCollectionImpl{result.value()};
  return ZVEC_OK;
}

ZvecStatus zvec_open_collection(const char *path, ZvecCollection *out) {
  if (!path || !out)
    return ZVEC_ERROR_INVALID_PARAM;

  zvec::CollectionOptions options;
  auto result = zvec::Collection::Open(path, options);

  if (!result.has_value()) {
    std::string message = result.error().message();
    std::string lowered = message;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    if (lowered.find("lock") != std::string::npos) {
      LOGI("Writable open failed due to lock issue, retrying read-only: %s",
           message.c_str());
      zvec::CollectionOptions read_only_options(/*read_only=*/true,
                                                /*enable_mmap=*/true);
      auto read_only_result = zvec::Collection::Open(path, read_only_options);
      if (read_only_result.has_value()) {
        LOGI("Opened collection at %s in read-only mode", path);
        *out = new ZvecCollectionImpl{read_only_result.value()};
        return ZVEC_OK;
      }

      LOGE("Read-only retry also failed at %s: %s", path,
           read_only_result.error().message().c_str());
      return convert_status(read_only_result.error());
    }
  }

  if (!result.has_value()) {
    LOGE("Failed to open collection at %s: %s", path,
         result.error().message().c_str());
    return convert_status(result.error());
  }

  LOGI("Opened collection at %s", path);
  *out = new ZvecCollectionImpl{result.value()};
  return ZVEC_OK;
}

ZvecStatus zvec_close_collection(ZvecCollection coll) {
  if (!coll)
    return ZVEC_OK;
  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  delete impl;
  return ZVEC_OK;
}

ZvecStatus zvec_flush(ZvecCollection coll) {
  if (!coll)
    return ZVEC_ERROR_INVALID_PARAM;

  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);
  return convert_status(impl->collection->Flush());
}

ZvecStatus zvec_optimize(ZvecCollection coll) {
  if (!coll)
    return ZVEC_ERROR_INVALID_PARAM;

  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);
  auto status = impl->collection->Optimize();
  if (!status.ok()) {
    LOGE("Optimize failed: %s", status.message().c_str());
  }
  return convert_status(status);
}

int zvec_has_field(ZvecCollection coll, const char *field) {
  if (!coll || !field)
    return 0;
  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);
  auto schema = impl->collection->Schema();
  if (schema && schema->has_field(field)) {
    return 1;
  }
  return 0;
}

ZvecStatus zvec_destroy(ZvecCollection coll) {
  if (!coll)
    return ZVEC_ERROR_INVALID_PARAM;

  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  auto status = impl->collection->Destroy();
  delete impl;
  return convert_status(status);
}

// ============================================================================
// DOCUMENT OPERATIONS
// ============================================================================

// FNV-1a simple string hash for doc_id
static uint64_t hash_string(const std::string &str) {
  uint64_t hash = 14695981039346656037ULL;
  for (char c : str) {
    hash ^= (uint8_t)c;
    hash *= 1099511628211ULL;
  }
  return hash == 0 ? 1 : hash;
}

ZvecStatus zvec_insert(ZvecCollection coll, const char *id, const float *vector,
                       uint32_t dimension, const char *content,
                       const char *metadata_json, const char *hash_val) {
  if (!coll || !id || !vector || dimension == 0)
    return ZVEC_ERROR_INVALID_PARAM;

  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);

  zvec::Doc doc;
  doc.set_pk(id);
  // Hash collision safety (mixing dimension per feedback)
  doc.set_doc_id(hash_string(id) ^ dimension);

  doc.set("id", std::string(id));

  zvec::DataType vector_data_type = detect_vector_data_type(impl->collection);
  if (vector_data_type == zvec::DataType::VECTOR_FP32) {
    std::vector<float> vec_f32(vector, vector + dimension);
    doc.set("vector", std::move(vec_f32));
  } else {
    thread_local std::vector<zvec::float16_t> vec_f16;
    if (vec_f16.size() != dimension) {
      vec_f16.resize(dimension);
    }
    zvec::ailego::FloatHelper::ToFP16(
        vector, dimension, reinterpret_cast<uint16_t *>(vec_f16.data()));
    doc.set("vector", std::move(vec_f16));
  }

  if (content) {
    doc.set("content", std::string(content));
  }

  if (metadata_json) {
    doc.set("metadata", std::string(metadata_json));
  }

  if (hash_val) {
    doc.set("hash", std::string(hash_val));
  }

  std::vector<zvec::Doc> docs = {std::move(doc)};
  LOGI("zvec_insert: id='%s', hash='%s', dim=%u", id,
       hash_val ? hash_val : "NULL", dimension);
  auto result = impl->collection->Upsert(docs);

  if (!result.has_value()) {
    LOGE("Insert failed for ID %s: %s", id, result.error().message().c_str());
    return convert_status(result.error());
  }

  for (auto &st : result.value()) {
    if (!st.ok()) {
      LOGE("Insert chunk failed for ID %s: %s", id, st.message().c_str());
      return convert_status(st);
    }
  }

  // Safety flush for mobile persistence - REMOVED for bulk performance
  // impl->collection->Flush();

  return ZVEC_OK;
}

// ============================================================================
// BATCH OPERATIONS
// ============================================================================

ZvecStatus zvec_insert_batch(ZvecCollection coll, const char **ids,
                             const float *vectors, const char **hashes,
                             uint32_t dimension, uint32_t count) {
  if (!coll || !ids || !vectors || count == 0 || dimension == 0)
    return ZVEC_ERROR_INVALID_PARAM;

  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);

  std::vector<zvec::Doc> docs;
  docs.reserve(count);
  zvec::DataType vector_data_type = detect_vector_data_type(impl->collection);

  for (uint32_t i = 0; i < count; ++i) {
    zvec::Doc doc;
    const char *id = ids[i];
    if (!id || *id == '\0') {
      set_error("zvec_insert_batch: ids contains null/empty entry");
      return ZVEC_ERROR_INVALID_PARAM;
    }
    doc.set_pk(id);
    doc.set_doc_id(hash_string(id) ^ dimension);
    doc.set("id", std::string(id));

    if (vector_data_type == zvec::DataType::VECTOR_FP32) {
      const float *src = &vectors[i * dimension];
      std::vector<float> vec_f32(src, src + dimension);
      doc.set("vector", std::move(vec_f32));
    } else {
      thread_local std::vector<zvec::float16_t> vec_f16;
      if (vec_f16.size() != dimension) {
        vec_f16.resize(dimension);
      }
      zvec::ailego::FloatHelper::ToFP16(
          &vectors[i * dimension], dimension,
          reinterpret_cast<uint16_t *>(vec_f16.data()));
      doc.set("vector", std::move(vec_f16));
    }

    if (hashes && hashes[i]) {
      doc.set("hash", std::string(hashes[i]));
    }

    docs.push_back(std::move(doc));
  }

  auto result = impl->collection->Upsert(docs);

  if (!result.has_value()) {
    LOGE("Batch insert failed: %s", result.error().message().c_str());
    return convert_status(result.error());
  }

  for (auto &st : result.value()) {
    if (!st.ok()) {
      LOGE("Batch chunk insert failed: %s", st.message().c_str());
      return convert_status(st);
    }
  }

  impl->collection->Flush();
  return ZVEC_OK;
}

ZvecStatus zvec_delete(ZvecCollection coll, const char *id) {
  if (!coll || !id)
    return ZVEC_ERROR_INVALID_PARAM;
  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);

  std::vector<std::string> pks = {std::string(id)};
  auto result = impl->collection->Delete(pks);

  if (!result.has_value()) {
    LOGE("Delete failed for ID %s: %s", id, result.error().message().c_str());
    return convert_status(result.error());
  }

  for (auto &st : result.value()) {
    if (!st.ok())
      return convert_status(st);
  }

  return ZVEC_OK;
}

ZvecStatus zvec_delete_by_filter(ZvecCollection coll, const char *filter) {
  if (!coll || !filter)
    return ZVEC_ERROR_INVALID_PARAM;
  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);

  auto status = impl->collection->DeleteByFilter(std::string(filter));
  if (!status.ok()) {
    LOGE("DeleteFilter failed (%s): %s", filter, status.message().c_str());
  }
  return convert_status(status);
}

// ============================================================================
// SEARCH
// ============================================================================

ZvecStatus zvec_search(ZvecCollection coll, const float *query,
                       uint32_t dimension, uint32_t topk, const char *filter,
                       ZvecSearchResult **results, uint32_t *out_count) {
  return zvec_search_with_threshold(coll, query, dimension, topk, -3.4e38f,
                                    filter, results, out_count);
}

ZvecStatus zvec_search_with_threshold(ZvecCollection coll, const float *query,
                                      uint32_t dimension, uint32_t topk,
                                      float min_score, const char *filter,
                                      ZvecSearchResult **results,
                                      uint32_t *out_count) {
  if (!coll || !query || !results || !out_count || dimension == 0)
    return ZVEC_ERROR_INVALID_PARAM;

  *results = nullptr;
  *out_count = 0;

  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);

  zvec::VectorQuery vq;
  vq.topk_ = topk;
  if (!filter) {
    // Small expansion for better recall without filter
    vq.topk_ = std::min(topk + 4, 64u);
  }
  vq.field_name_ = "vector";
  vq.query_vector_ = encode_query_vector(impl->collection, query, dimension);

  // Only fetch fields we need
  static const std::vector<std::string> default_output_fields{"id", "metadata", "content"};
  vq.output_fields_ = default_output_fields;
  vq.include_vector_ = false;

  // Tune ef_search: scale with topk but cap for latency
  if (filter) {
    vq.filter_ = std::string(filter);
    uint32_t ef_search = std::max(48u, std::min(192u, topk * 4));
    auto hqp = std::make_shared<zvec::HnswQueryParams>(
        ef_search, min_score > -100.0f ? min_score : -2.0f, false, false);
    vq.query_params_ = hqp;
  } else {
    uint32_t ef_search = std::max(48u, std::min(128u, topk * 3));
    auto hqp =
        std::make_shared<zvec::HnswQueryParams>(ef_search, -2.0f, false, false);
    vq.query_params_ = hqp;
  }

  auto result = impl->collection->Query(vq);
  if (filter && (!result.has_value() || result.value().empty())) {
    // Fallback to FLAT linear scan if HNSW with filter produced no results
    // (could be index lag or strict filtering)
    LOGI("zvec_search_with_threshold: HNSW+Filter returned 0, falling back to "
         "FLAT scan");
    auto fqp = std::make_shared<zvec::FlatQueryParams>();
    fqp->set_is_linear(true);
    fqp->set_radius(min_score > -100.0f ? min_score : -100000.0f);
    vq.query_params_ = fqp;
    result = impl->collection->Query(vq);
  }

  if (!result.has_value()) {
    LOGE("Search query failed: %s", result.error().message().c_str());
    return convert_status(result.error());
  }

  auto docs = result.value();

  // Filter by min_score
  std::vector<zvec::Doc::Ptr> filtered;
  filtered.reserve(docs.size());
  for (auto &_doc : docs) {
    if (_doc->score() >= min_score) {
      filtered.push_back(_doc);
    }
  }

  if (filtered.empty()) {
    return ZVEC_OK;
  }

  *out_count = (uint32_t)filtered.size();
  *results =
      (ZvecSearchResult *)malloc(sizeof(ZvecSearchResult) * (*out_count));
  if (!*results) {
    set_error("zvec_search_with_threshold: out of memory allocating results");
    *out_count = 0;
    return ZVEC_ERROR_INTERNAL;
  }

  size_t i = 0;
  for (auto &d : filtered) {
    ZvecSearchResult &res = (*results)[i++];
    res.id = copy_string(d->pk());
    res.score = d->score();

    auto content = d->get<std::string>("content");
    res.content = content ? copy_string(*content) : nullptr;

    auto meta = d->get<std::string>("metadata");
    res.metadata = meta ? copy_string(*meta) : nullptr;
  }

  return ZVEC_OK;
}

ZvecStatus zvec_list_sources(ZvecCollection coll, uint32_t dimension,
                             ZvecSearchResult **results, uint32_t *out_count) {
  if (!coll || !results || !out_count || dimension == 0)
    return ZVEC_ERROR_INVALID_PARAM;

  *results = nullptr;
  *out_count = 0;

  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);

  auto stats = impl->collection->Stats();
  if (stats.has_value() && stats.value().doc_count == 0) {
    return ZVEC_OK;
  }

  // We query with a dummy non-zero vector since HNSW Inner Product might reject
  // a 0-magnitude query. We also limit topk to a reasonable bound representing
  // typical UI pagination.
  // Dummy non-zero vector since HNSW Inner Product might reject
  // a 0-magnitude query.

  // LOGI removed for latency

  zvec::VectorQuery vq;
  vq.topk_ = 100; // Mobile-optimized listing limit
  vq.field_name_ = "vector";

  // Use a strictly normalized dummy vector
  thread_local std::vector<float> query_vec_f32;
  if (query_vec_f32.size() != dimension) {
    query_vec_f32.assign(dimension, 0.0f);
  } else {
    // Zero out efficiently
    std::fill(query_vec_f32.begin(), query_vec_f32.end(), 0.0f);
  }
  query_vec_f32[0] = 1.0f;

  vq.query_vector_ =
      encode_query_vector(impl->collection, query_vec_f32.data(), dimension);
  vq.output_fields_ = std::vector<std::string>{"id", "metadata", "content"};
  vq.include_vector_ = false;
  auto hqp = std::make_shared<zvec::HnswQueryParams>(256, -2.0f, false, false);
  vq.query_params_ = hqp;

  // Try with default params first
  auto result = impl->collection->Query(vq);

  if (!result.has_value()) {
    LOGI("zvec_list_sources: Primary query FAILED: %s",
         result.error().message().c_str());
    return convert_status(result.error());
  }

  auto docs = result.value();
  if (docs.empty()) {
    LOGI("zvec_list_sources: Primary query returned 0; skipping fallback "
         "vector scans and returning empty list");
    return ZVEC_OK;
  }

  if (!result.has_value()) {
    return convert_status(result.error());
  }

  LOGI("zvec_list_sources: Final docs found: %zu", docs.size());

  if (docs.empty()) {
    return ZVEC_OK;
  }

  *out_count = (uint32_t)docs.size();
  *results =
      (ZvecSearchResult *)malloc(sizeof(ZvecSearchResult) * (*out_count));
  if (!*results) {
    set_error("zvec_list_sources: out of memory allocating results");
    *out_count = 0;
    return ZVEC_ERROR_INTERNAL;
  }

  size_t i = 0;
  for (auto &d : docs) {
    ZvecSearchResult &res = (*results)[i++];
    res.id = copy_string(d->pk());
    res.score = 1.0f; // Score not relevant for listing

    auto content = d->get<std::string>("content");
    res.content = content ? copy_string(*content) : nullptr;

    auto meta = d->get<std::string>("metadata");
    res.metadata = meta ? copy_string(*meta) : nullptr;
  }

  return ZVEC_OK;
}

ZvecStatus zvec_fetch(ZvecCollection coll, const char **ids, uint32_t count,
                      ZvecSearchResult **results, uint32_t *out_count) {
  if (!coll || !ids || count == 0 || !results || !out_count)
    return ZVEC_ERROR_INVALID_PARAM;

  *results = nullptr;
  *out_count = 0;

  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);

  std::vector<std::string> pks;
  for (uint32_t i = 0; i < count; ++i) {
    if (ids[i]) {
      pks.push_back(std::string(ids[i]));
    }
  }

  if (pks.empty()) {
    return ZVEC_OK;
  }

  auto fetch_res = impl->collection->Fetch(pks);
  if (!fetch_res.has_value()) {
    return convert_status(fetch_res.error());
  }

  auto doc_map = fetch_res.value();
  std::vector<zvec::Doc::Ptr> found_docs;
  // Preserve requested order by iterating over the input keys
  for (const auto &pk : pks) {
    auto it = doc_map.find(pk);
    if (it != doc_map.end() && it->second != nullptr) {
      found_docs.push_back(it->second);
    }
  }

  if (found_docs.empty()) {
    return ZVEC_OK;
  }

  *out_count = (uint32_t)found_docs.size();
  *results =
      (ZvecSearchResult *)malloc(sizeof(ZvecSearchResult) * (*out_count));
  if (!*results) {
    set_error("zvec_fetch: out of memory allocating results");
    *out_count = 0;
    return ZVEC_ERROR_INTERNAL;
  }

  size_t i = 0;
  for (auto &d : found_docs) {
    ZvecSearchResult &res = (*results)[i++];
    res.id = copy_string(d->pk());
    res.score = 1.0f; // Score not relevant for fetch

    auto content = d->get<std::string>("content");
    res.content = content ? copy_string(*content) : nullptr;

    auto meta = d->get<std::string>("metadata");
    res.metadata = meta ? copy_string(*meta) : nullptr;
  }

  return ZVEC_OK;
}

// ============================================================================
// STATS
// ============================================================================

ZvecStatus zvec_count(ZvecCollection coll, uint64_t *out_count) {
  if (!coll || !out_count)
    return ZVEC_ERROR_INVALID_PARAM;
  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);

  auto stats = impl->collection->Stats();
  if (!stats.has_value()) {
    return convert_status(stats.error());
  }

  *out_count = stats.value().doc_count;
  return ZVEC_OK;
}

// ============================================================================
// MEMORY MANAGEMENT
// ============================================================================

void zvec_free_string(char *str) {
  if (str)
    free(str);
}

void zvec_free_results(ZvecSearchResult *results, uint32_t count) {
  if (!results)
    return;
  for (uint32_t i = 0; i < count; ++i) {
    zvec_free_string(results[i].id);
    zvec_free_string(results[i].metadata);
    zvec_free_string(results[i].content);
  }
  free(results);
}

uint32_t zvec_get_dimension(ZvecCollection coll) {
  if (!coll)
    return 0;
  auto impl = static_cast<ZvecCollectionImpl *>(coll);
  std::lock_guard<std::mutex> lock(impl->mutex);
  auto schema_res = impl->collection->Schema();
  if (!schema_res.has_value()) {
    return 0;
  }
  auto schema = schema_res.value();
  auto vector_fields = schema.vector_fields();
  if (vector_fields.empty()) {
    return 0;
  }
  // We assume the first vector field is our primary one
  return vector_fields[0]->dimension();
}
