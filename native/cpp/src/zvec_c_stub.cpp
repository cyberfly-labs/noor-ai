// Stub implementation of zvec_c.h when Zvec libraries are not available.
// All functions return ZVEC_ERROR_NOT_SUPPORTED.

#include "zvec_c.h"
#include <cstddef>

namespace {

constexpr char kZvecUnsupportedError[] =
  "Zvec support is disabled in this build";

} // namespace

ZvecStatus zvec_create_collection(const char *, const char *, uint32_t,
                                  ZvecCollection *out) {
  if (out) *out = nullptr;
  return ZVEC_ERROR_NOT_SUPPORTED;
}

ZvecStatus zvec_open_collection(const char *, ZvecCollection *out) {
  if (out) *out = nullptr;
  return ZVEC_ERROR_NOT_SUPPORTED;
}

ZvecStatus zvec_close_collection(ZvecCollection) { return ZVEC_OK; }
ZvecStatus zvec_flush(ZvecCollection) { return ZVEC_ERROR_NOT_SUPPORTED; }
ZvecStatus zvec_optimize(ZvecCollection) { return ZVEC_ERROR_NOT_SUPPORTED; }
int zvec_has_field(ZvecCollection, const char *) { return 0; }
ZvecStatus zvec_destroy(ZvecCollection) { return ZVEC_OK; }

ZvecStatus zvec_insert(ZvecCollection, const char *, const float *, uint32_t,
                       const char *, const char *, const char *) {
  return ZVEC_ERROR_NOT_SUPPORTED;
}

ZvecStatus zvec_insert_batch(ZvecCollection, const char **, const float *,
                             const char **, uint32_t, uint32_t) {
  return ZVEC_ERROR_NOT_SUPPORTED;
}

ZvecStatus zvec_delete(ZvecCollection, const char *) {
  return ZVEC_ERROR_NOT_SUPPORTED;
}

ZvecStatus zvec_delete_by_filter(ZvecCollection, const char *) {
  return ZVEC_ERROR_NOT_SUPPORTED;
}

ZvecStatus zvec_fetch(ZvecCollection, const char **, uint32_t,
                      ZvecSearchResult **, uint32_t *) {
  return ZVEC_ERROR_NOT_SUPPORTED;
}

ZvecStatus zvec_search(ZvecCollection, const float *, uint32_t, uint32_t,
                       const char *, ZvecSearchResult **, uint32_t *) {
  return ZVEC_ERROR_NOT_SUPPORTED;
}

ZvecStatus zvec_search_with_threshold(ZvecCollection, const float *, uint32_t,
                                      uint32_t, float, const char *,
                                      ZvecSearchResult **, uint32_t *) {
  return ZVEC_ERROR_NOT_SUPPORTED;
}

ZvecStatus zvec_list_sources(ZvecCollection, uint32_t, ZvecSearchResult **,
                             uint32_t *) {
  return ZVEC_ERROR_NOT_SUPPORTED;
}

ZvecStatus zvec_count(ZvecCollection, uint64_t *out) {
  if (out) *out = 0;
  return ZVEC_ERROR_NOT_SUPPORTED;
}

uint32_t zvec_get_dimension(ZvecCollection) { return 0; }
void zvec_free_string(char *) {}
void zvec_free_results(ZvecSearchResult *, uint32_t) {}
const char *zvec_get_last_error(void) { return kZvecUnsupportedError; }
