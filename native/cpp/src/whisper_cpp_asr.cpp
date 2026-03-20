#include "whisper_cpp_asr.h"

#include "ggml-backend.h"
#include "whisper.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <mutex>
#include <sstream>
#include <thread>
#include <vector>

namespace {

constexpr const char *kDefaultModelFileName = "ggml-tiny.en-q5_1.bin";
constexpr int kExpectedSampleRateHz = 16000;
constexpr int kChunkDurationMs = 3000;
constexpr int kChunkOverlapMs = 500;
constexpr size_t kChunkSampleCount =
  (static_cast<size_t>(kChunkDurationMs) * kExpectedSampleRateHz) / 1000U;
constexpr size_t kChunkStrideSampleCount =
  ((static_cast<size_t>(kChunkDurationMs) - kChunkOverlapMs) *
   kExpectedSampleRateHz) / 1000U;
constexpr float kSpeechEnergyThreshold = 0.0005f;
constexpr size_t kMinOverlapChars = 8;

bool fileExists(const std::string &path) {
  std::ifstream file(path, std::ios::binary);
  return file.good();
}

bool endsWith(const std::string &value, const std::string &suffix) {
  return value.size() >= suffix.size() &&
         value.compare(value.size() - suffix.size(), suffix.size(), suffix) == 0;
}

std::string joinPath(const std::string &base, const std::string &name) {
  if (base.empty()) {
    return name;
  }
  if (base.back() == '/') {
    return base + name;
  }
  return base + "/" + name;
}

std::string trimWhitespace(const std::string &value) {
  size_t start = 0;
  while (start < value.size() &&
         std::isspace(static_cast<unsigned char>(value[start])) != 0) {
    ++start;
  }

  size_t end = value.size();
  while (end > start &&
         std::isspace(static_cast<unsigned char>(value[end - 1])) != 0) {
    --end;
  }

  return value.substr(start, end - start);
}

std::string trimLeadingWhitespace(const std::string &value) {
  size_t start = 0;
  while (start < value.size() &&
         std::isspace(static_cast<unsigned char>(value[start])) != 0) {
    ++start;
  }

  return value.substr(start);
}

bool equalsIgnoreCase(char left, char right) {
  return std::tolower(static_cast<unsigned char>(left)) ==
         std::tolower(static_cast<unsigned char>(right));
}

bool isBoundaryChar(char value) {
  const unsigned char ch = static_cast<unsigned char>(value);
  return std::isspace(ch) != 0 || std::ispunct(ch) != 0;
}

bool endsWithInsensitive(const std::string &value, const std::string &suffix) {
  if (suffix.empty() || suffix.size() > value.size()) {
    return false;
  }

  const size_t offset = value.size() - suffix.size();
  for (size_t index = 0; index < suffix.size(); ++index) {
    if (!equalsIgnoreCase(value[offset + index], suffix[index])) {
      return false;
    }
  }

  return true;
}

size_t findOverlapChars(const std::string &combined_text,
                        const std::string &chunk_text) {
  if (combined_text.empty() || chunk_text.empty()) {
    return 0;
  }

  const size_t max_overlap = std::min(combined_text.size(), chunk_text.size());
  for (size_t overlap = max_overlap; overlap >= kMinOverlapChars; --overlap) {
    const size_t combined_offset = combined_text.size() - overlap;
    if (combined_offset > 0 && !isBoundaryChar(combined_text[combined_offset - 1])) {
      continue;
    }
    if (overlap < chunk_text.size() && !isBoundaryChar(chunk_text[overlap])) {
      continue;
    }

    bool matches = true;
    for (size_t index = 0; index < overlap; ++index) {
      if (!equalsIgnoreCase(combined_text[combined_offset + index],
                            chunk_text[index])) {
        matches = false;
        break;
      }
    }

    if (matches) {
      return overlap;
    }
  }

  return 0;
}

std::string resolveModelPath(const std::string &model_dir_or_file) {
  if (model_dir_or_file.empty()) {
    return {};
  }

  if (fileExists(model_dir_or_file) && endsWith(model_dir_or_file, ".bin")) {
    return model_dir_or_file;
  }

  const std::string candidate = joinPath(model_dir_or_file, kDefaultModelFileName);
  if (fileExists(candidate)) {
    return candidate;
  }

  return {};
}

uint16_t readU16Le(std::istream &input) {
  uint8_t bytes[2] = {0, 0};
  input.read(reinterpret_cast<char *>(bytes), sizeof(bytes));
  return static_cast<uint16_t>(bytes[0]) |
         (static_cast<uint16_t>(bytes[1]) << 8);
}

uint32_t readU32Le(std::istream &input) {
  uint8_t bytes[4] = {0, 0, 0, 0};
  input.read(reinterpret_cast<char *>(bytes), sizeof(bytes));
  return static_cast<uint32_t>(bytes[0]) |
         (static_cast<uint32_t>(bytes[1]) << 8) |
         (static_cast<uint32_t>(bytes[2]) << 16) |
         (static_cast<uint32_t>(bytes[3]) << 24);
}

bool readWaveFile(const std::string &path, std::vector<float> &samples,
                  std::string &error) {
  std::ifstream file(path, std::ios::binary);
  if (!file.is_open()) {
    error = "Failed to open WAV file: " + path;
    return false;
  }

  char riff[4] = {0, 0, 0, 0};
  file.read(riff, sizeof(riff));
  if (file.gcount() != static_cast<std::streamsize>(sizeof(riff)) ||
      std::strncmp(riff, "RIFF", sizeof(riff)) != 0) {
    error = "Invalid WAV file: missing RIFF header";
    return false;
  }

  (void)readU32Le(file);

  char wave[4] = {0, 0, 0, 0};
  file.read(wave, sizeof(wave));
  if (file.gcount() != static_cast<std::streamsize>(sizeof(wave)) ||
      std::strncmp(wave, "WAVE", sizeof(wave)) != 0) {
    error = "Invalid WAV file: missing WAVE signature";
    return false;
  }

  uint16_t audio_format = 0;
  uint16_t channel_count = 0;
  uint32_t sample_rate = 0;
  uint16_t bits_per_sample = 0;
  std::vector<uint8_t> raw_audio;

  while (file.good()) {
    char chunk_id[4] = {0, 0, 0, 0};
    file.read(chunk_id, sizeof(chunk_id));
    if (file.gcount() != static_cast<std::streamsize>(sizeof(chunk_id))) {
      break;
    }

    const uint32_t chunk_size = readU32Le(file);

    if (std::strncmp(chunk_id, "fmt ", sizeof(chunk_id)) == 0) {
      audio_format = readU16Le(file);
      channel_count = readU16Le(file);
      sample_rate = readU32Le(file);
      (void)readU32Le(file);
      (void)readU16Le(file);
      bits_per_sample = readU16Le(file);

      const std::streamoff remaining = static_cast<std::streamoff>(chunk_size) - 16;
      if (remaining > 0) {
        file.seekg(remaining, std::ios::cur);
      }
    } else if (std::strncmp(chunk_id, "data", sizeof(chunk_id)) == 0) {
      raw_audio.resize(chunk_size);
      file.read(reinterpret_cast<char *>(raw_audio.data()),
                static_cast<std::streamsize>(chunk_size));
      if (file.gcount() != static_cast<std::streamsize>(chunk_size)) {
        error = "Invalid WAV file: truncated data chunk";
        return false;
      }
    } else {
      file.seekg(static_cast<std::streamoff>(chunk_size), std::ios::cur);
    }

    if ((chunk_size & 1U) != 0U) {
      file.seekg(1, std::ios::cur);
    }
  }

  if (audio_format == 0 || channel_count == 0 || bits_per_sample == 0 ||
      raw_audio.empty()) {
    error = "Invalid WAV file: missing fmt or data chunk";
    return false;
  }

  if (sample_rate != kExpectedSampleRateHz) {
    error = "Expected 16 kHz audio, got " + std::to_string(sample_rate) + " Hz";
    return false;
  }

  if (audio_format == 1 && bits_per_sample == 16) {
    const size_t frame_count =
        raw_audio.size() / (sizeof(int16_t) * static_cast<size_t>(channel_count));
    samples.resize(frame_count);
    const auto *pcm = reinterpret_cast<const int16_t *>(raw_audio.data());
    for (size_t frame = 0; frame < frame_count; ++frame) {
      int32_t mixed = 0;
      for (uint16_t channel = 0; channel < channel_count; ++channel) {
        mixed += pcm[frame * channel_count + channel];
      }
      const float averaged =
          static_cast<float>(mixed) / static_cast<float>(channel_count);
      samples[frame] = averaged / 32768.0f;
    }
    return true;
  }

  if (audio_format == 3 && bits_per_sample == 32) {
    const size_t frame_count =
        raw_audio.size() / (sizeof(float) * static_cast<size_t>(channel_count));
    samples.resize(frame_count);
    const auto *pcm = reinterpret_cast<const float *>(raw_audio.data());
    for (size_t frame = 0; frame < frame_count; ++frame) {
      float mixed = 0.0f;
      for (uint16_t channel = 0; channel < channel_count; ++channel) {
        mixed += pcm[frame * channel_count + channel];
      }
      samples[frame] = mixed / static_cast<float>(channel_count);
    }
    return true;
  }

  std::ostringstream message;
  message << "Unsupported WAV format: audio_format=" << audio_format
          << ", bits_per_sample=" << bits_per_sample;
  error = message.str();
  return false;
}

int recommendedThreadCount() {
  const unsigned int hardware_threads = std::thread::hardware_concurrency();
  if (hardware_threads == 0U) {
    return 4;
  }

  if (hardware_threads >= 4U) {
    return 4;
  }

  return std::max(2, static_cast<int>(hardware_threads));
}

bool hasSpeechEnergy(const float *samples, size_t sample_count) {
  if (samples == nullptr || sample_count == 0U) {
    return false;
  }

  double energy_sum = 0.0;
  for (size_t index = 0; index < sample_count; ++index) {
    energy_sum += static_cast<double>(samples[index]) *
                  static_cast<double>(samples[index]);
  }

  const float average_energy =
      static_cast<float>(energy_sum / static_cast<double>(sample_count));
  return average_energy > kSpeechEnergyThreshold;
}

int selectBestToken(const float *logits, int vocab_size) {
  if (logits == nullptr || vocab_size <= 0) {
    return -1;
  }

  int best_token = 0;
  float best_score = logits[0];
  for (int index = 1; index < vocab_size; ++index) {
    if (logits[index] > best_score) {
      best_score = logits[index];
      best_token = index;
    }
  }

  return best_token;
}

bool transcribeChunkStreaming(struct whisper_context *context,
                              struct whisper_state *state,
                              int mel_offset,
                              int n_threads,
                              int language_id,
                              int &n_past,
                              std::vector<whisper_token> &decode_input,
                              std::string &text,
                              std::string &error) {
  text.clear();
  error.clear();

  if (context == nullptr || state == nullptr) {
    error = "ASR model is not loaded";
    return false;
  }

  if (whisper_encode_with_state(context, state, mel_offset, n_threads) != 0) {
    error = "Failed to run whisper.cpp encoder";
    return false;
  }

  if (language_id < 0) {
    error = "Failed to resolve English language token";
    return false;
  }

  if (decode_input.empty()) {
    decode_input = {
        whisper_token_sot(context),
        whisper_token_lang(context, language_id),
        whisper_token_transcribe(context),
        whisper_token_not(context),
    };
    n_past = 0;
  }

  std::vector<whisper_token> generated_tokens;
  generated_tokens.reserve(32);

  const whisper_token end_token = whisper_token_eot(context);
  constexpr int kMaxDecodeSteps = 32;

  for (int step = 0; step < kMaxDecodeSteps; ++step) {
    if (whisper_decode_with_state(context, state, decode_input.data(),
                                  static_cast<int>(decode_input.size()), n_past,
                                  n_threads) != 0) {
      error = "Failed to run whisper.cpp decoder";
      return false;
    }

    n_past += static_cast<int>(decode_input.size());

    const float *logits = whisper_get_logits_from_state(state);
    const int best_token = selectBestToken(logits, whisper_n_vocab(context));
    if (best_token < 0) {
      error = "Decoder returned invalid logits";
      return false;
    }

    if (best_token == end_token) {
      break;
    }

    generated_tokens.push_back(static_cast<whisper_token>(best_token));
    decode_input.clear();
    decode_input.push_back(static_cast<whisper_token>(best_token));
  }

  for (const whisper_token token : generated_tokens) {
    const char *token_text = whisper_token_to_str(context, token);
    if (token_text != nullptr) {
      text += token_text;
    }
  }

  text = trimWhitespace(text);
  return true;
}

bool appendChunkText(std::string &combined_text, const std::string &chunk_text) {
  const std::string trimmed = trimWhitespace(chunk_text);
  if (trimmed.empty()) {
    return false;
  }

  if (combined_text.empty()) {
    combined_text = trimmed;
    return true;
  }

  if (endsWithInsensitive(combined_text, trimmed)) {
    return false;
  }

  const size_t overlap_chars = findOverlapChars(combined_text, trimmed);
  std::string suffix = overlap_chars > 0
      ? trimLeadingWhitespace(trimmed.substr(overlap_chars))
      : trimmed;
  if (suffix.empty()) {
    return false;
  }

  if (!combined_text.empty() &&
      !std::isspace(static_cast<unsigned char>(combined_text.back())) &&
      !std::ispunct(static_cast<unsigned char>(suffix.front()))) {
    combined_text.push_back(' ');
  }
  combined_text += suffix;
  return true;
}

void ensureBackendsLoaded() {
  static std::once_flag once;
  std::call_once(once, []() { ggml_backend_load_all(); });
}

} // namespace

namespace edgemind {

WhisperCppAsr::WhisperCppAsr() = default;

WhisperCppAsr::~WhisperCppAsr() {
  reset();
}

void WhisperCppAsr::reset() {
  if (context_ != nullptr) {
    whisper_free(context_);
    context_ = nullptr;
  }
  model_path_.clear();
}

bool WhisperCppAsr::load(const std::string &model_dir_or_file,
                         std::string &error) {
  error.clear();
  reset();

  model_path_ = resolveModelPath(model_dir_or_file);
  if (model_path_.empty()) {
    error = "Unable to locate whisper.cpp model. Expected " +
            std::string(kDefaultModelFileName) + " in " + model_dir_or_file;
    return false;
  }

  ensureBackendsLoaded();

  std::fprintf(stderr,
               "EdgeMind ASR: loading whisper.cpp model=%s gpu_requested=1 flash_attn=1\n",
               model_path_.c_str());
  std::fprintf(stderr, "EdgeMind ASR: system_info=%s\n",
               whisper_print_system_info());

  whisper_context_params context_params = whisper_context_default_params();
  context_params.use_gpu = true;
  context_params.flash_attn = true;

  context_ = whisper_init_from_file_with_params(model_path_.c_str(), context_params);
  if (context_ == nullptr) {
    std::fprintf(stderr,
                 "EdgeMind ASR: GPU init failed for %s, falling back to CPU\n",
                 model_path_.c_str());
    context_params.use_gpu = false;
    context_params.flash_attn = false;
    context_ = whisper_init_from_file_with_params(model_path_.c_str(), context_params);
  }

  if (context_ == nullptr) {
    error = "Failed to initialize whisper.cpp context from " + model_path_;
    return false;
  }

  std::fprintf(stderr,
               "EdgeMind ASR: whisper.cpp context initialized gpu_requested=%d flash_attn=%d model=%s\n",
               context_params.use_gpu ? 1 : 0,
               context_params.flash_attn ? 1 : 0,
               model_path_.c_str());

  return true;
}

bool WhisperCppAsr::transcribeFile(const std::string &wav_path, std::string &text,
                                   std::string &error,
                                   const WhisperPartialCallback &partial_callback) {
  error.clear();
  text.clear();

  if (context_ == nullptr) {
    error = "ASR model is not loaded";
    return false;
  }

  std::vector<float> samples;
  if (!readWaveFile(wav_path, samples, error)) {
    return false;
  }

  const int n_threads = recommendedThreadCount();
  const int language_id = whisper_lang_id("en");
  if (language_id < 0) {
    error = "Failed to resolve English language token";
    return false;
  }

  struct whisper_state *state = whisper_init_state(context_);
  if (state == nullptr) {
    error = "Failed to allocate whisper.cpp state";
    return false;
  }

  if (whisper_pcm_to_mel_with_state(context_, state, samples.data(),
                                    static_cast<int>(samples.size()),
                                    n_threads) != 0) {
    whisper_free_state(state);
    error = "Failed to compute full-audio log-mel spectrogram";
    return false;
  }

  std::string combined_text;
  std::vector<whisper_token> decode_input;
  int n_past = 0;
  for (size_t offset = 0; offset < samples.size(); offset += kChunkStrideSampleCount) {
    const size_t chunk_length =
        std::min(kChunkSampleCount, samples.size() - offset);
    const float *chunk_samples = samples.data() + offset;

    if (!hasSpeechEnergy(chunk_samples, chunk_length)) {
      continue;
    }

    std::string chunk_text;
    const int mel_offset = static_cast<int>((offset * 100U) /
                        kExpectedSampleRateHz);
    if (!transcribeChunkStreaming(context_, state, mel_offset, n_threads,
                                  language_id, n_past, decode_input,
                                  chunk_text, error)) {
      whisper_free_state(state);
      return false;
    }

    const bool appended = appendChunkText(combined_text, chunk_text);
    if (partial_callback && appended) {
      partial_callback(combined_text, false);
    }
  }

  whisper_free_state(state);

  text = trimWhitespace(combined_text);
  if (partial_callback) {
    partial_callback(text, true);
  }
  return true;
}

} // namespace edgemind