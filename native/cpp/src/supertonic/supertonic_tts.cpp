// Supertonic TTS - Diffusion-based Neural TTS with MNN
// Based on supertonic-mnn by yunfengwang (OpenRAIL License)
// C++ port for EdgeMind on-device inference

#include "supertonic_tts.h"

#include <MNN/MNNForwardType.h>
#include <MNN/expr/Executor.hpp>
#include <MNN/expr/ExprCreator.hpp>
#include <MNN/expr/Module.hpp>

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>
#include <fstream>
#include <random>
#include <regex>
#include <sstream>

#ifdef ANDROID
#include <android/log.h>
#define STTS_LOG(...) __android_log_print(ANDROID_LOG_INFO, "SupertonicTTS", __VA_ARGS__)
#else
#define STTS_LOG(...) fprintf(stderr, __VA_ARGS__), fprintf(stderr, "\n")
#endif

using namespace MNN;
using namespace MNN::Express;

// ─── Simple JSON parser helpers ─────────────────────────────────────────────
// We only need to parse simple JSON files (tts.json, unicode_indexer.json,
// voice style .json). We avoid pulling in a full JSON library by doing
// minimal parsing.

namespace {

// Trim whitespace
static std::string trim(const std::string &s) {
  auto start = s.find_first_not_of(" \t\n\r");
  if (start == std::string::npos) return "";
  auto end = s.find_last_not_of(" \t\n\r");
  return s.substr(start, end - start + 1);
}

// Read entire file into a string
static std::string readFile(const std::string &path) {
  std::ifstream f(path, std::ios::binary);
  if (!f.is_open()) return "";
  std::ostringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

// Minimal JSON: extract integer value for a key like "sample_rate": 44100
static bool jsonGetInt(const std::string &json, const std::string &key,
                       int &out) {
  std::string pat = "\"" + key + "\"";
  auto pos = json.find(pat);
  if (pos == std::string::npos) return false;
  pos = json.find(':', pos + pat.size());
  if (pos == std::string::npos) return false;
  pos++;
  while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t'))
    pos++;
  // Read number (possibly negative)
  std::string num;
  if (pos < json.size() && json[pos] == '-') {
    num += '-';
    pos++;
  }
  while (pos < json.size() && json[pos] >= '0' && json[pos] <= '9') {
    num += json[pos++];
  }
  if (num.empty() || num == "-") return false;
  out = std::stoi(num);
  return true;
}

// Parse unicode_indexer.json: {"48": 23, "49": 24, ...}
// Keys are string unicode codepoints, values are token indices
static bool parseUnicodeIndexer(const std::string &json,
                                std::unordered_map<int, int> &indexer) {
  indexer.clear();
  auto skip_ws = [&](size_t &pos) {
    while (pos < json.size() &&
           (json[pos] == ' ' || json[pos] == '\t' || json[pos] == '\n' ||
            json[pos] == '\r')) {
      pos++;
    }
  };

  size_t pos = 0;
  skip_ws(pos);
  if (pos >= json.size()) return false;

  if (json[pos] == '[') {
    // Actual HF file format: [ -1, -1, 23, ... ] where the array index is the
    // Unicode code point and values < 0 mean "unknown / unmapped".
    pos++;
    int codepoint = 0;
    while (pos < json.size()) {
      skip_ws(pos);
      if (pos >= json.size() || json[pos] == ']') break;

      bool negative = false;
      if (json[pos] == '-') {
        negative = true;
        pos++;
      }

      std::string val_str;
      while (pos < json.size() && json[pos] >= '0' && json[pos] <= '9') {
        val_str += json[pos++];
      }
      if (val_str.empty()) return false;

      int val = std::stoi(val_str);
      if (negative) val = -val;
      if (val >= 0) {
        indexer[codepoint] = val;
      }
      codepoint++;

      skip_ws(pos);
      if (pos < json.size() && json[pos] == ',') pos++;
    }
    return !indexer.empty();
  }

  if (json[pos] != '{') return false;
  pos++;

  while (pos < json.size()) {
    while (pos < json.size() &&
           (json[pos] == ' ' || json[pos] == '\t' || json[pos] == '\n' ||
            json[pos] == '\r' || json[pos] == ',')) {
      pos++;
    }
    if (pos >= json.size() || json[pos] == '}') break;

    if (json[pos] != '"') break;
    pos++;
    std::string key_str;
    while (pos < json.size() && json[pos] != '"') {
      key_str += json[pos++];
    }
    if (pos >= json.size()) break;
    pos++;

    while (pos < json.size() && json[pos] != ':') pos++;
    if (pos >= json.size()) break;
    pos++;

    skip_ws(pos);

    std::string val_str;
    if (pos < json.size() && json[pos] == '-') {
      val_str += '-';
      pos++;
    }
    while (pos < json.size() && json[pos] >= '0' && json[pos] <= '9') {
      val_str += json[pos++];
    }

    if (!key_str.empty() && !val_str.empty()) {
      int key = std::stoi(key_str);
      int val = std::stoi(val_str);
      if (val >= 0) {
        indexer[key] = val;
      }
    }
  }
  return !indexer.empty();
}

// Parse a voice style JSON file:
// {"style_ttl": {"dims": [1, D1, D2], "data": [...]},
//  "style_dp":  {"dims": [1, D1, D2], "data": [...]}}
static bool parseStyleField(const std::string &json, const std::string &field,
                            std::vector<float> &data,
                            std::vector<int> &dims) {
  std::string pat = "\"" + field + "\"";
  auto pos = json.find(pat);
  if (pos == std::string::npos) return false;

  auto object_start = json.find('{', pos);
  if (object_start == std::string::npos) return false;

  int object_depth = 1;
  auto object_end = object_start + 1;
  while (object_end < json.size() && object_depth > 0) {
    if (json[object_end] == '{') object_depth++;
    else if (json[object_end] == '}') object_depth--;
    object_end++;
  }
  if (object_depth != 0) return false;

  std::string field_json =
      json.substr(object_start, object_end - object_start);

  auto dims_pos = field_json.find("\"dims\"");
  if (dims_pos == std::string::npos) return false;
  auto bracket = field_json.find('[', dims_pos);
  if (bracket == std::string::npos) return false;
  auto bracket_end = field_json.find(']', bracket);
  if (bracket_end == std::string::npos) return false;

  dims.clear();
  std::string dims_str =
      field_json.substr(bracket + 1, bracket_end - bracket - 1);
  std::istringstream ds(dims_str);
  std::string token;
  while (std::getline(ds, token, ',')) {
    dims.push_back(std::stoi(trim(token)));
  }

  auto data_pos = field_json.find("\"data\"");
  if (data_pos == std::string::npos) return false;
  auto data_bracket = field_json.find('[', data_pos);
  if (data_bracket == std::string::npos) return false;

  int depth = 1;
  auto p = data_bracket + 1;
  while (p < field_json.size() && depth > 0) {
    if (field_json[p] == '[') depth++;
    else if (field_json[p] == ']') depth--;
    p++;
  }
  if (depth != 0) return false;
  auto data_bracket_end = p - 1;

  data.clear();
  std::string data_str =
      field_json.substr(data_bracket + 1, data_bracket_end - data_bracket - 1);

  const char *c = data_str.c_str();
  const char *end = c + data_str.size();
  while (c < end) {
    while (c < end && (*c == ' ' || *c == ',' || *c == '\n' || *c == '\r' ||
                       *c == '\t' || *c == '[' || *c == ']'))
      c++;
    if (c >= end) break;
    char *next;
    float val = strtof(c, &next);
    if (next == c) break;
    data.push_back(val);
    c = next;
  }

  if (dims.empty() || data.empty()) return false;

  size_t expected_values = 1;
  for (int dim : dims) {
    if (dim <= 0) return false;
    expected_values *= static_cast<size_t>(dim);
  }
  return expected_values == data.size();
}

// Text preprocessing: simplified version of the Python UnicodeProcessor
static std::string preprocessText(const std::string &text) {
  std::string out = text;

  // Replace common special characters
  // Various dashes → hyphen
  // Smart quotes → ASCII quotes
  // etc.
  auto replace_all = [](std::string &s, const std::string &from,
                         const std::string &to) {
    size_t pos = 0;
    while ((pos = s.find(from, pos)) != std::string::npos) {
      s.replace(pos, from.size(), to);
      pos += to.size();
    }
  };

  replace_all(out, "\xe2\x80\x93", "-");  // –
  replace_all(out, "\xe2\x80\x91", "-");  // ‑
  replace_all(out, "\xe2\x80\x94", "-");  // —
  replace_all(out, "\xc2\xaf", " ");      // ¯
  replace_all(out, "_", " ");
  replace_all(out, "\xe2\x80\x9c", "\""); // "
  replace_all(out, "\xe2\x80\x9d", "\""); // "
  replace_all(out, "\xe2\x80\x98", "'");  // '
  replace_all(out, "\xe2\x80\x99", "'");  // '
  replace_all(out, "\xc2\xb4", "'");      // ´
  replace_all(out, "`", "'");
  replace_all(out, "[", " ");
  replace_all(out, "]", " ");
  replace_all(out, "|", " ");
  replace_all(out, "/", " ");
  replace_all(out, "#", " ");
  replace_all(out, "@", " at ");

  // Remove extra spaces
  std::string cleaned;
  bool prevSpace = false;
  for (char c : out) {
    if (c == ' ' || c == '\t') {
      if (!prevSpace) cleaned += ' ';
      prevSpace = true;
    } else {
      cleaned += c;
      prevSpace = false;
    }
  }

  // Trim
  out = trim(cleaned);

  // If text doesn't end with punctuation, add a period
  if (!out.empty()) {
    char last = out.back();
    if (last != '.' && last != '!' && last != '?' && last != ';' &&
        last != ':' && last != ',' && last != '"' && last != '\'') {
      out += '.';
    }
  }

  return out;
}

// Split text into chunks (simplified version of chunk_text)
static std::vector<std::string> chunkText(const std::string &text,
                                          int max_len = 300) {
  std::vector<std::string> chunks;
  if (text.empty()) return chunks;

  // Split by sentence boundaries
  std::vector<std::string> sentences;
  std::string current;
  for (size_t i = 0; i < text.size(); i++) {
    current += text[i];
    // Check for sentence-ending punctuation followed by space or end
    if ((text[i] == '.' || text[i] == '!' || text[i] == '?') &&
        (i + 1 >= text.size() || text[i + 1] == ' ')) {
      sentences.push_back(trim(current));
      current.clear();
    }
  }
  if (!current.empty()) {
    sentences.push_back(trim(current));
  }

  // Combine sentences into chunks respecting max_len
  std::string chunk;
  for (auto &s : sentences) {
    if (chunk.empty()) {
      chunk = s;
    } else if ((int)(chunk.size() + 1 + s.size()) <= max_len) {
      chunk += " " + s;
    } else {
      if (!chunk.empty()) chunks.push_back(chunk);
      chunk = s;
    }
  }
  if (!chunk.empty()) chunks.push_back(chunk);

  return chunks;
}

// Create a length-to-mask tensor: shape [B, 1, max_len]
static std::vector<float> lengthToMask(const std::vector<int> &lengths,
                                       int max_len) {
  int B = (int)lengths.size();
  std::vector<float> mask(B * max_len, 0.0f);
  for (int b = 0; b < B; b++) {
    for (int i = 0; i < lengths[b] && i < max_len; i++) {
      mask[b * max_len + i] = 1.0f;
    }
  }
  return mask;
}

// Create VARP from float data
static VARP createVARP(const float *data, const std::vector<int> &shape) {
  auto var = _Input(shape, NCHW, halide_type_of<float>());
  auto ptr = var->writeMap<float>();
  int total = 1;
  for (int d : shape) total *= d;
  std::memcpy(ptr, data, total * sizeof(float));
  return var;
}

// Create VARP from int data (as int32)
static VARP createVARPInt(const int *data, const std::vector<int> &shape) {
  auto var = _Input(shape, NCHW, halide_type_of<int>());
  auto ptr = var->writeMap<int>();
  int total = 1;
  for (int d : shape) total *= d;
  std::memcpy(ptr, data, total * sizeof(int));
  return var;
}

} // anonymous namespace

// ─── SupertonicTTS Implementation ──────────────────────────────────────────

SupertonicTTS::SupertonicTTS() = default;

SupertonicTTS::~SupertonicTTS() {
  dp_model_.reset();
  text_enc_model_.reset();
  vector_est_model_.reset();
  vocoder_model_.reset();
  rt_manager_.reset();
}

int SupertonicTTS::load(const char *model_dir, const char *voice,
                        int num_threads) {
  std::string base(model_dir);
  std::string models_dir = base + "/mnn_models";
  std::string precision_dir = models_dir + "/int8";

  // ── 1. Load tts.json config ──
  std::string tts_json = readFile(models_dir + "/tts.json");
  if (tts_json.empty()) {
    STTS_LOG("Failed to read tts.json from %s", models_dir.c_str());
    return -1;
  }

  int sr = 44100, bcs = 512, ld = 24, ccf = 6;
  jsonGetInt(tts_json, "sample_rate", sr);

  // Navigate to ae.base_chunk_size
  auto ae_pos = tts_json.find("\"ae\"");
  if (ae_pos != std::string::npos) {
    std::string ae_section = tts_json.substr(ae_pos);
    jsonGetInt(ae_section, "sample_rate", sr);
    jsonGetInt(ae_section, "base_chunk_size", bcs);
    int ae_ldim = 24;
    jsonGetInt(ae_section, "ldim", ae_ldim);
    ld = ae_ldim;
  }

  // Navigate to ttl.chunk_compress_factor
  auto ttl_pos = tts_json.find("\"ttl\"");
  if (ttl_pos != std::string::npos) {
    std::string ttl_section = tts_json.substr(ttl_pos);
    jsonGetInt(ttl_section, "chunk_compress_factor", ccf);
    int ttl_ld = 24;
    jsonGetInt(ttl_section, "latent_dim", ttl_ld);
    ld = ttl_ld;
  }

  sample_rate_ = sr;
  base_chunk_size_ = bcs;
  latent_dim_ = ld;
  chunk_compress_factor_ = ccf;

  STTS_LOG("TTS config: sr=%d bcs=%d ld=%d ccf=%d", sample_rate_,
           base_chunk_size_, latent_dim_, chunk_compress_factor_);

  // ── 2. Load unicode indexer ──
  std::string indexer_json = readFile(models_dir + "/unicode_indexer.json");
  if (indexer_json.empty()) {
    STTS_LOG("Failed to read unicode_indexer.json");
    return -2;
  }
  if (!parseUnicodeIndexer(indexer_json, unicode_indexer_)) {
    STTS_LOG("Failed to parse unicode_indexer.json");
    return -2;
  }
  STTS_LOG("Loaded %zu unicode index entries", unicode_indexer_.size());

  // ── 3. Load voice style ──
  std::string voice_path = base + "/voice_styles/" + std::string(voice) + ".json";
  std::string style_json = readFile(voice_path);
  if (style_json.empty()) {
    STTS_LOG("Failed to read voice style: %s", voice_path.c_str());
    return -3;
  }

  if (!parseStyleField(style_json, "style_ttl", style_ttl_, style_ttl_dims_) ||
      !parseStyleField(style_json, "style_dp", style_dp_, style_dp_dims_)) {
    STTS_LOG("Failed to parse voice style fields");
    return -3;
  }
  STTS_LOG("Voice style loaded: ttl dims=[%d,%d,%d], dp dims=[%d,%d,%d]",
           style_ttl_dims_[0], style_ttl_dims_[1], style_ttl_dims_[2],
           style_dp_dims_[0], style_dp_dims_[1], style_dp_dims_[2]);

  // ── 4. Create MNN runtime manager ──
  ScheduleConfig sched;
  sched.type = MNN_FORWARD_CPU;
  sched.numThread = num_threads;

  BackendConfig bnConfig;
  bnConfig.precision = BackendConfig::Precision_Low;
  bnConfig.memory = BackendConfig::Memory_Low;
  sched.backendConfig = &bnConfig;

  auto *rtmgr = Executor::RuntimeManager::createRuntimeManager(sched);
  if (!rtmgr) {
    STTS_LOG("Failed to create MNN RuntimeManager");
    return -4;
  }
  rt_manager_.reset(rtmgr, Executor::RuntimeManager::destroy);

  // ── 5. Load MNN models ──
  auto loadModule = [&](const std::string &path,
                        const std::vector<std::string> &inputs,
                        const std::vector<std::string> &outputs)
      -> std::shared_ptr<Module> {
    auto *mod = Module::load(inputs, outputs, path.c_str(), rt_manager_);
    if (!mod) {
      STTS_LOG("Failed to load MNN model: %s", path.c_str());
      return nullptr;
    }
    return std::shared_ptr<Module>(mod, Module::destroy);
  };

  dp_model_ = loadModule(precision_dir + "/duration_predictor.mnn",
                          {"text_ids", "style_dp", "text_mask"}, {"duration"});
  if (!dp_model_) return -5;

  text_enc_model_ =
      loadModule(precision_dir + "/text_encoder.mnn",
                 {"text_ids", "style_ttl", "text_mask"}, {"text_emb"});
  if (!text_enc_model_) return -5;

  vector_est_model_ = loadModule(
      precision_dir + "/vector_estimator.mnn",
      {"noisy_latent", "text_emb", "style_ttl", "latent_mask", "text_mask",
       "current_step", "total_step"},
      {"denoised_latent"});
  if (!vector_est_model_) return -5;

  vocoder_model_ = loadModule(precision_dir + "/vocoder.mnn", {"latent"},
                              {"wav_tts"});
  if (!vocoder_model_) return -5;

  STTS_LOG("All 4 MNN models loaded successfully");
  loaded_ = true;
  return 0;
}

void SupertonicTTS::synthesize(const char *text, float speed,
                               int denoise_steps,
                               std::vector<float> &pcm_out) {
  pcm_out.clear();
  if (!loaded_ || !text || std::strlen(text) == 0) return;

  // Preprocess and chunk text
  std::string processed = preprocessText(text);
  auto chunks = chunkText(processed);
  if (chunks.empty()) return;

  // Silence between chunks (0.3 seconds)
  const float silence_duration = 0.3f;
  const int silence_samples = (int)(silence_duration * sample_rate_);

  std::mt19937 rng(42); // Fixed seed for reproducibility
  std::normal_distribution<float> normal(0.0f, 1.0f);

  for (size_t ci = 0; ci < chunks.size(); ci++) {
    const auto &chunk = chunks[ci];
    if (chunk.empty()) continue;

    // ── Text to IDs ──
    std::vector<int> text_ids;
    for (size_t i = 0; i < chunk.size();) {
      // Decode UTF-8 to codepoint
      unsigned char c = chunk[i];
      int codepoint = 0;
      int bytes = 0;
      if (c < 0x80) {
        codepoint = c;
        bytes = 1;
      } else if ((c & 0xE0) == 0xC0) {
        codepoint = c & 0x1F;
        bytes = 2;
      } else if ((c & 0xF0) == 0xE0) {
        codepoint = c & 0x0F;
        bytes = 3;
      } else if ((c & 0xF8) == 0xF0) {
        codepoint = c & 0x07;
        bytes = 4;
      } else {
        i++;
        continue; // Skip invalid
      }
      for (int j = 1; j < bytes && i + j < chunk.size(); j++) {
        codepoint = (codepoint << 6) | (chunk[i + j] & 0x3F);
      }
      i += bytes;

      auto it = unicode_indexer_.find(codepoint);
      if (it != unicode_indexer_.end()) {
        text_ids.push_back(it->second);
      }
      // Unknown chars are skipped (like Python version)
    }

    if (text_ids.empty()) continue;

    int text_len = (int)text_ids.size();
    int bsz = 1;

    // Create text mask: [1, 1, text_len]
    std::vector<float> text_mask(text_len, 1.0f);

    // Create style VARP tensors
    VARP style_dp_var =
        createVARP(style_dp_.data(), {style_dp_dims_[0], style_dp_dims_[1],
                                      style_dp_dims_[2]});
    VARP style_ttl_var =
        createVARP(style_ttl_.data(), {style_ttl_dims_[0], style_ttl_dims_[1],
                                       style_ttl_dims_[2]});
    VARP text_ids_var = createVARPInt(text_ids.data(), {bsz, text_len});
    VARP text_mask_var = createVARP(text_mask.data(), {bsz, 1, text_len});

    // ── Duration Predictor ──
    auto dp_out = dp_model_->onForward({text_ids_var, style_dp_var, text_mask_var});
    if (dp_out.empty()) {
      STTS_LOG("Duration predictor failed for chunk %zu", ci);
      continue;
    }

    // Read duration value
    auto *dur_info = dp_out[0]->getInfo();
    const float *dur_data = dp_out[0]->readMap<float>();
    if (!dur_data || !dur_info) continue;

    // Duration is total seconds; apply speed
    float duration = dur_data[0] / speed;
    if (duration <= 0.0f) continue;

    // ── Text Encoder ──
    auto te_out =
        text_enc_model_->onForward({text_ids_var, style_ttl_var, text_mask_var});
    if (te_out.empty()) {
      STTS_LOG("Text encoder failed for chunk %zu", ci);
      continue;
    }

    // ── Sample Noisy Latent ──
    float wav_len_max = duration * sample_rate_;
    int chunk_size = base_chunk_size_ * chunk_compress_factor_;
    int latent_len = (int)std::ceil(wav_len_max / chunk_size);
    int latent_dim = latent_dim_ * chunk_compress_factor_;

    // Create latent mask: [1, 1, latent_len]
    int64_t wav_length = (int64_t)(duration * sample_rate_);
    int latent_length =
        (int)((wav_length + (int64_t)chunk_size - 1) / (int64_t)chunk_size);
    latent_len = latent_length;

    std::vector<float> latent_mask_data(latent_len, 1.0f);
    VARP latent_mask_var =
        createVARP(latent_mask_data.data(), {bsz, 1, latent_len});

    // Random noisy latent: [1, latent_dim, latent_len]
    std::vector<float> noisy_latent(latent_dim * latent_len);
    for (auto &v : noisy_latent) {
      v = normal(rng);
    }
    // Apply latent mask (all ones for single utterance, so no-op effectively)
    VARP xt_var =
        createVARP(noisy_latent.data(), {bsz, latent_dim, latent_len});

    // ── Denoising Loop ──
    std::vector<float> total_step_data(bsz, (float)denoise_steps);
    VARP total_step_var = createVARP(total_step_data.data(), {bsz});

    for (int step = 0; step < denoise_steps; step++) {
      std::vector<float> current_step_data(bsz, (float)step);
      VARP current_step_var = createVARP(current_step_data.data(), {bsz});

      auto ve_out = vector_est_model_->onForward(
          {xt_var, te_out[0], style_ttl_var, latent_mask_var, text_mask_var,
           current_step_var, total_step_var});
      if (ve_out.empty()) {
        STTS_LOG("Vector estimator failed at step %d for chunk %zu", step, ci);
        break;
      }
      xt_var = ve_out[0];
    }

    // ── Vocoder ──
    auto voc_out = vocoder_model_->onForward({xt_var});
    if (voc_out.empty()) {
      STTS_LOG("Vocoder failed for chunk %zu", ci);
      continue;
    }

    auto *wav_info = voc_out[0]->getInfo();
    const float *wav_data = voc_out[0]->readMap<float>();
    if (!wav_data || !wav_info) continue;

    int wav_samples = 1;
    for (int d : wav_info->dim) wav_samples *= d;

    // Append to output
    pcm_out.insert(pcm_out.end(), wav_data, wav_data + wav_samples);

    // Add silence between chunks (but not after the last one)
    if (ci + 1 < chunks.size()) {
      pcm_out.resize(pcm_out.size() + silence_samples, 0.0f);
    }
  }

  STTS_LOG("Synthesized %zu samples at %d Hz", pcm_out.size(), sample_rate_);
}
