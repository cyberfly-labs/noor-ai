#include "sherpa_mnn_asr.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <fstream>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <utility>
#include <vector>

#include "rapidjson/document.h"
#include "sherpa-mnn/c-api/cxx-api.h"
#ifdef EDGEMIND_RNNOISE_AVAILABLE
#include "rnnoise.h"
#endif

namespace edgemind {
namespace {

struct StreamingModelFiles {
  std::string encoder = "encoder-epoch-99-avg-1.mnn";
  std::string decoder = "decoder-epoch-99-avg-1.mnn";
  std::string joiner = "joiner-epoch-99-avg-1.mnn";
  std::string tokens = "tokens.txt";
};

struct WhisperModelFiles {
  std::string encoder = "encode.mnn";
  std::string decoder = "decode.mnn";
  std::string tokens; // resolved at runtime
};

/// Known whisper token file names, checked in order.
static const char *kWhisperTokenCandidates[] = {
    "tiny.en-tokens.txt",
  "base-tokens.txt",
};

enum class RecognizerMode {
  kNone,
  kStreaming,
  kOfflineWhisper,
};

bool pathExists(const std::string &path) {
  struct stat info;
  return stat(path.c_str(), &info) == 0;
}

std::string joinPath(const std::string &base, const std::string &leaf) {
  if (base.empty()) {
    return leaf;
  }

  if (base.back() == '/') {
    return base + leaf;
  }

  return base + "/" + leaf;
}

std::string trim(std::string value) {
  const auto is_space = [](unsigned char ch) {
    return std::isspace(ch) != 0;
  };

  value.erase(value.begin(),
              std::find_if(value.begin(), value.end(), [&](unsigned char ch) {
                return !is_space(ch);
              }));

  value.erase(std::find_if(value.rbegin(), value.rend(),
                           [&](unsigned char ch) { return !is_space(ch); })
                  .base(),
              value.end());

  return value;
}

std::string appendTranscriptSegment(const std::string &prefix,
                                   const std::string &segment) {
  if (segment.empty()) {
    return prefix;
  }

  if (prefix.empty()) {
    return segment;
  }

  return prefix + " " + segment;
}

bool parseStreamingModelFiles(const std::string &config_path,
                              StreamingModelFiles &files,
                              std::string &error) {
  std::ifstream input(config_path);
  if (!input.is_open()) {
    return true;
  }

  std::ostringstream buffer;
  buffer << input.rdbuf();

  rapidjson::Document document;
  if (document.Parse(buffer.str().c_str()).HasParseError() ||
      !document.IsObject()) {
    error = "Invalid sherpa-mnn config.json";
    return false;
  }

  if (document.HasMember("transducer") && document["transducer"].IsObject()) {
    const auto &transducer = document["transducer"];
    if (transducer.HasMember("encoder") && transducer["encoder"].IsString()) {
      files.encoder = transducer["encoder"].GetString();
    }
    if (transducer.HasMember("decoder") && transducer["decoder"].IsString()) {
      files.decoder = transducer["decoder"].GetString();
    }
    if (transducer.HasMember("joiner") && transducer["joiner"].IsString()) {
      files.joiner = transducer["joiner"].GetString();
    }
  }

  if (document.HasMember("tokens") && document["tokens"].IsString()) {
    files.tokens = document["tokens"].GetString();
  }

  return true;
}

int32_t recommendedThreadCount() {
  const unsigned int hardware_threads = std::thread::hardware_concurrency();
  if (hardware_threads == 0) {
    return 2;
  }

  return static_cast<int32_t>(std::max(1u, std::min(4u, hardware_threads)));
}

constexpr int32_t kAsrSampleRate = 16000;
constexpr int32_t kDecodeChunkSamples = 8000;

#ifdef EDGEMIND_RNNOISE_AVAILABLE
bool preprocessForAsrWithRnnoise(const std::vector<float> &input,
                                 int32_t sample_rate,
                                 std::vector<float> &output,
                                 std::string &error);

bool maybePreprocessForAsr(bool rnnoise_enabled,
                           const std::vector<float> &input,
                           int32_t sample_rate,
                           const std::vector<float> *&audio_samples,
                           std::vector<float> &scratch,
                           std::string &error) {
  if (!rnnoise_enabled) {
    audio_samples = &input;
    return true;
  }

  if (!preprocessForAsrWithRnnoise(input, sample_rate, scratch, error)) {
    return false;
  }

  audio_samples = &scratch;
  return true;
}
#endif

#ifdef EDGEMIND_RNNOISE_AVAILABLE
bool warmUpRnnoise(std::string &error) {
  DenoiseState *state = rnnoise_create(nullptr);
  if (!state) {
    error = "Failed to create RNNoise denoiser state";
    return false;
  }

  rnnoise_destroy(state);
  return true;
}
#endif

bool warmUpOnlineRecognizer(sherpa_mnn::cxx::OnlineRecognizer &recognizer,
                            bool rnnoise_enabled, std::string &error) {
  constexpr int32_t kWarmupSamples = kDecodeChunkSamples * 3;
  std::vector<float> silence(kWarmupSamples, 0.0f);

  const std::vector<float> *audio_samples = &silence;

#ifdef EDGEMIND_RNNOISE_AVAILABLE
  std::vector<float> denoised_silence;
  if (!maybePreprocessForAsr(rnnoise_enabled, silence, kAsrSampleRate,
                             audio_samples, denoised_silence, error)) {
    return false;
  }
#endif

  auto stream = recognizer.CreateStream();
  const int32_t total_samples = static_cast<int32_t>(audio_samples->size());
  for (int32_t offset = 0; offset < total_samples;
       offset += kDecodeChunkSamples) {
    const int32_t chunk_size =
        std::min(kDecodeChunkSamples, total_samples - offset);
    stream.AcceptWaveform(kAsrSampleRate, audio_samples->data() + offset,
                          chunk_size);

    while (recognizer.IsReady(&stream)) {
      recognizer.Decode(&stream);
      if (recognizer.IsEndpoint(&stream)) {
        recognizer.Reset(&stream);
      }
    }
  }

  stream.InputFinished();
  while (recognizer.IsReady(&stream)) {
    recognizer.Decode(&stream);
    if (recognizer.IsEndpoint(&stream)) {
      recognizer.Reset(&stream);
    }
  }

  (void)recognizer.GetResult(&stream);
  recognizer.Reset(&stream);
  return true;
}

bool warmUpOfflineRecognizer(sherpa_mnn::cxx::OfflineRecognizer &recognizer,
                             bool rnnoise_enabled, std::string &error) {
  constexpr int32_t kWarmupSamples = kAsrSampleRate * 2;
  std::vector<float> silence(kWarmupSamples, 0.0f);

  const std::vector<float> *audio_samples = &silence;

#ifdef EDGEMIND_RNNOISE_AVAILABLE
  std::vector<float> denoised_silence;
  if (!maybePreprocessForAsr(rnnoise_enabled, silence, kAsrSampleRate,
                             audio_samples, denoised_silence, error)) {
    return false;
  }
#endif

  auto stream = recognizer.CreateStream();
  stream.AcceptWaveform(kAsrSampleRate, audio_samples->data(),
                        static_cast<int32_t>(audio_samples->size()));
  recognizer.Decode(&stream);
  (void)recognizer.GetResult(&stream);
  return true;
}

#ifdef EDGEMIND_RNNOISE_AVAILABLE
constexpr int32_t kRnnoiseSampleRate = 48000;
constexpr float kRnnoiseWetMix = 0.75f;

std::vector<float> resampleLinear(const std::vector<float> &input,
                                  int32_t input_rate,
                                  int32_t output_rate) {
  if (input.empty() || input_rate <= 0 || output_rate <= 0 ||
      input_rate == output_rate) {
    return input;
  }

  const double scale = static_cast<double>(output_rate) /
                       static_cast<double>(input_rate);
  const size_t output_size = std::max<size_t>(
      1, static_cast<size_t>(std::llround(input.size() * scale)));

  std::vector<float> output(output_size);
  for (size_t index = 0; index < output_size; ++index) {
    const double source_position =
        static_cast<double>(index) / static_cast<double>(output_rate) *
        static_cast<double>(input_rate);
    const size_t lower_index = std::min<size_t>(
        static_cast<size_t>(source_position), input.size() - 1);
    const size_t upper_index =
        std::min<size_t>(lower_index + 1, input.size() - 1);
    const double alpha = source_position - static_cast<double>(lower_index);
    output[index] = static_cast<float>(
        input[lower_index] * (1.0 - alpha) + input[upper_index] * alpha);
  }

  return output;
}

bool preprocessForAsrWithRnnoise(const std::vector<float> &input,
                                 int32_t sample_rate,
                                 std::vector<float> &output,
                                 std::string &error) {
  if (input.empty()) {
    output.clear();
    return true;
  }

  if (sample_rate <= 0) {
    error = "Invalid WAV sample rate for RNNoise preprocessing";
    return false;
  }

  DenoiseState *state = rnnoise_create(nullptr);
  if (!state) {
    error = "Failed to create RNNoise denoiser state";
    return false;
  }

  const int32_t frame_size = rnnoise_get_frame_size();
  if (frame_size <= 0) {
    rnnoise_destroy(state);
    error = "RNNoise returned an invalid frame size";
    return false;
  }

  const std::vector<float> resampled =
      resampleLinear(input, sample_rate, kRnnoiseSampleRate);
  std::vector<float> denoised(resampled.size());
  std::vector<float> input_frame(frame_size, 0.0f);
  std::vector<float> output_frame(frame_size, 0.0f);

  for (size_t offset = 0; offset < resampled.size();
       offset += static_cast<size_t>(frame_size)) {
    std::fill(input_frame.begin(), input_frame.end(), 0.0f);
    std::fill(output_frame.begin(), output_frame.end(), 0.0f);

    const size_t chunk_size = std::min<size_t>(
        static_cast<size_t>(frame_size), resampled.size() - offset);
    for (size_t index = 0; index < chunk_size; ++index) {
      input_frame[index] =
          std::clamp(resampled[offset + index], -1.0f, 1.0f) * 32767.0f;
    }

    rnnoise_process_frame(state, output_frame.data(), input_frame.data());

    for (size_t index = 0; index < chunk_size; ++index) {
      const float dry = resampled[offset + index];
      const float wet = std::clamp(output_frame[index] / 32767.0f, -1.0f, 1.0f);
      denoised[offset + index] =
          std::clamp(wet * kRnnoiseWetMix + dry * (1.0f - kRnnoiseWetMix),
                     -1.0f, 1.0f);
    }
  }

  rnnoise_destroy(state);

  output = resampleLinear(denoised, kRnnoiseSampleRate, sample_rate);
  if (output.size() > input.size()) {
    output.resize(input.size());
  } else if (output.size() < input.size()) {
    output.insert(output.end(), input.size() - output.size(), 0.0f);
  }

  return true;
}
#endif

} // namespace

class SherpaMnnAsr::Impl {
public:
  explicit Impl(bool rnnoise_enabled) : rnnoise_enabled_(rnnoise_enabled) {}

  bool load(const std::string &model_dir, std::string &error) {
    streaming_recognizer_.reset();
    offline_whisper_recognizer_.reset();
    mode_ = RecognizerMode::kNone;
    backend_name_.clear();

    StreamingModelFiles streaming_files;
    const std::string config_path = joinPath(model_dir, "config.json");
    std::string config_error;
    if (pathExists(config_path) &&
        !parseStreamingModelFiles(config_path, streaming_files, config_error)) {
      streaming_files = StreamingModelFiles();
    }

    const bool has_streaming_bundle =
        pathExists(joinPath(model_dir, streaming_files.encoder)) &&
        pathExists(joinPath(model_dir, streaming_files.decoder)) &&
        pathExists(joinPath(model_dir, streaming_files.joiner)) &&
        pathExists(joinPath(model_dir, streaming_files.tokens));

    WhisperModelFiles whisper_files;
    // Auto-detect which whisper tokens file is present.
    for (const auto *candidate : kWhisperTokenCandidates) {
      if (pathExists(joinPath(model_dir, candidate))) {
        whisper_files.tokens = candidate;
        break;
      }
    }
    const bool has_whisper_bundle =
        !whisper_files.tokens.empty() &&
        pathExists(joinPath(model_dir, whisper_files.encoder)) &&
        pathExists(joinPath(model_dir, whisper_files.decoder));

    if (has_whisper_bundle) {
      return loadOfflineWhisperRecognizer(model_dir, whisper_files, error);
    }

    if (has_streaming_bundle) {
      if (!config_error.empty()) {
        error = config_error;
        return false;
      }

      return loadStreamingRecognizer(model_dir, streaming_files, error);
    }

    if (!config_error.empty()) {
      error = config_error;
      return false;
    }

    error = "Missing supported sherpa-mnn ASR model files in " + model_dir;
    return false;
  }

  bool transcribeFile(const std::string &wav_path, std::string &text,
                      std::string &error,
                      const AsrPartialCallback &partial_callback) {
    switch (mode_) {
    case RecognizerMode::kStreaming:
      return transcribeStreamingFile(wav_path, text, error, partial_callback);
    case RecognizerMode::kOfflineWhisper:
      return transcribeOfflineWhisperFile(wav_path, text, error,
                                          partial_callback);
    case RecognizerMode::kNone:
      error = "sherpa-mnn recognizer is not loaded";
      return false;
    }

    error = "Unsupported sherpa-mnn recognizer mode";
    return false;
  }

  std::string backendName() const {
    return backend_name_.empty() ? "sherpa-mnn" : backend_name_;
  }

private:
  bool loadStreamingRecognizer(const std::string &model_dir,
                               const StreamingModelFiles &files,
                               std::string &error) {
    const std::string encoder_path = joinPath(model_dir, files.encoder);
    const std::string decoder_path = joinPath(model_dir, files.decoder);
    const std::string joiner_path = joinPath(model_dir, files.joiner);
    const std::string tokens_path = joinPath(model_dir, files.tokens);

    if (!pathExists(encoder_path) || !pathExists(decoder_path) ||
        !pathExists(joiner_path) || !pathExists(tokens_path)) {
      error = "Missing sherpa-mnn model files in " + model_dir;
      return false;
    }

    sherpa_mnn::cxx::OnlineRecognizerConfig config;
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    config.model_config.transducer.encoder = encoder_path;
    config.model_config.transducer.decoder = decoder_path;
    config.model_config.transducer.joiner = joiner_path;
    config.model_config.tokens = tokens_path;
    config.model_config.num_threads = recommendedThreadCount();
    config.model_config.provider = "cpu";
    config.decoding_method = "modified_beam_search";
    config.max_active_paths = 4;
    config.enable_endpoint = true;
    config.rule1_min_trailing_silence = 2.4f;
    config.rule2_min_trailing_silence = 1.2f;
    config.rule3_min_utterance_length = 20.0f;

    auto recognizer = sherpa_mnn::cxx::OnlineRecognizer::Create(config);
    if (!recognizer.Get()) {
      error = "Failed to create sherpa-mnn recognizer";
      return false;
    }

#ifdef EDGEMIND_RNNOISE_AVAILABLE
    if (rnnoise_enabled_ && !warmUpRnnoise(error)) {
      return false;
    }
#endif

    if (!warmUpOnlineRecognizer(recognizer, rnnoise_enabled_, error)) {
      return false;
    }

    streaming_recognizer_ = std::make_unique<sherpa_mnn::cxx::OnlineRecognizer>(
        std::move(recognizer));
    mode_ = RecognizerMode::kStreaming;
    backend_name_ = "sherpa-mnn-streaming";
    return true;
  }

  bool loadOfflineWhisperRecognizer(const std::string &model_dir,
                                    const WhisperModelFiles &files,
                                    std::string &error) {
    const std::string encoder_path = joinPath(model_dir, files.encoder);
    const std::string decoder_path = joinPath(model_dir, files.decoder);
    const std::string tokens_path = joinPath(model_dir, files.tokens);

    if (!pathExists(encoder_path) || !pathExists(decoder_path) ||
        !pathExists(tokens_path)) {
      error = "Missing sherpa-mnn Whisper model files in " + model_dir;
      return false;
    }

    sherpa_mnn::cxx::OfflineRecognizerConfig config;
    config.feat_config.sample_rate = kAsrSampleRate;
    config.feat_config.feature_dim = 80;
    config.model_config.whisper.encoder = encoder_path;
    config.model_config.whisper.decoder = decoder_path;
    config.model_config.whisper.language = "en";
    config.model_config.whisper.task = "transcribe";
    config.model_config.tokens = tokens_path;
    config.model_config.num_threads = recommendedThreadCount();
    config.model_config.provider = "cpu";

    auto recognizer = sherpa_mnn::cxx::OfflineRecognizer::Create(config);
    if (!recognizer.Get()) {
      error = "Failed to create sherpa-mnn Whisper recognizer";
      return false;
    }

#ifdef EDGEMIND_RNNOISE_AVAILABLE
    if (rnnoise_enabled_ && !warmUpRnnoise(error)) {
      return false;
    }
#endif

    if (!warmUpOfflineRecognizer(recognizer, rnnoise_enabled_, error)) {
      return false;
    }

    offline_whisper_recognizer_ =
        std::make_unique<sherpa_mnn::cxx::OfflineRecognizer>(
            std::move(recognizer));
    mode_ = RecognizerMode::kOfflineWhisper;
    backend_name_ = "sherpa-mnn-whisper";
    return true;
  }

  bool transcribeStreamingFile(const std::string &wav_path, std::string &text,
                               std::string &error,
                               const AsrPartialCallback &partial_callback) {
    if (!streaming_recognizer_ || !streaming_recognizer_->Get()) {
      error = "sherpa-mnn streaming recognizer is not loaded";
      return false;
    }

    auto wave = sherpa_mnn::cxx::ReadWave(wav_path);
    if (wave.samples.empty()) {
      error = "Failed to read WAV file: " + wav_path;
      return false;
    }

    const std::vector<float> *audio_samples = &wave.samples;
#ifdef EDGEMIND_RNNOISE_AVAILABLE
    std::vector<float> denoised_samples;
    if (!maybePreprocessForAsr(rnnoise_enabled_, wave.samples,
                               wave.sample_rate, audio_samples,
                               denoised_samples, error)) {
      return false;
    }
#endif

    auto stream = streaming_recognizer_->CreateStream();
    std::string finalized_text;
    std::string last_emitted_text;

    const auto emit_partial = [&](bool is_final) -> std::string {
      std::string current_text = trim(streaming_recognizer_->GetResult(&stream).text);
      const std::string cumulative_text =
          appendTranscriptSegment(finalized_text, current_text);
      if (partial_callback &&
          (is_final ||
           (!cumulative_text.empty() && cumulative_text != last_emitted_text))) {
        last_emitted_text = cumulative_text;
        partial_callback(cumulative_text, is_final);
      }
      return current_text;
    };

    const int32_t total_samples = static_cast<int32_t>(audio_samples->size());
    for (int32_t offset = 0; offset < total_samples;
         offset += kDecodeChunkSamples) {
      const int32_t chunk_size =
          std::min(kDecodeChunkSamples, total_samples - offset);
      stream.AcceptWaveform(wave.sample_rate, audio_samples->data() + offset,
                            chunk_size);

      while (streaming_recognizer_->IsReady(&stream)) {
        streaming_recognizer_->Decode(&stream);
        const std::string current_text = emit_partial(false);
        if (streaming_recognizer_->IsEndpoint(&stream)) {
          finalized_text = appendTranscriptSegment(finalized_text, current_text);
          last_emitted_text = finalized_text;
          streaming_recognizer_->Reset(&stream);
        }
      }
    }

    stream.InputFinished();
    while (streaming_recognizer_->IsReady(&stream)) {
      streaming_recognizer_->Decode(&stream);
      const std::string current_text = emit_partial(false);
      if (streaming_recognizer_->IsEndpoint(&stream)) {
        finalized_text = appendTranscriptSegment(finalized_text, current_text);
        last_emitted_text = finalized_text;
        streaming_recognizer_->Reset(&stream);
      }
    }

    text = appendTranscriptSegment(finalized_text,
                                   trim(streaming_recognizer_->GetResult(&stream).text));
    if (partial_callback) {
      partial_callback(text, true);
    }

    return true;
  }

  bool transcribeOfflineWhisperFile(
      const std::string &wav_path, std::string &text, std::string &error,
      const AsrPartialCallback &partial_callback) {
    if (!offline_whisper_recognizer_ || !offline_whisper_recognizer_->Get()) {
      error = "sherpa-mnn Whisper recognizer is not loaded";
      return false;
    }

    auto wave = sherpa_mnn::cxx::ReadWave(wav_path);
    if (wave.samples.empty()) {
      error = "Failed to read WAV file: " + wav_path;
      return false;
    }

    const std::vector<float> *audio_samples = &wave.samples;
#ifdef EDGEMIND_RNNOISE_AVAILABLE
    std::vector<float> denoised_samples;
    if (!maybePreprocessForAsr(rnnoise_enabled_, wave.samples,
                               wave.sample_rate, audio_samples,
                               denoised_samples, error)) {
      return false;
    }
#endif

    auto stream = offline_whisper_recognizer_->CreateStream();
    stream.AcceptWaveform(wave.sample_rate, audio_samples->data(),
                          static_cast<int32_t>(audio_samples->size()));
    offline_whisper_recognizer_->Decode(&stream);

    text = trim(offline_whisper_recognizer_->GetResult(&stream).text);
    if (partial_callback) {
      partial_callback(text, true);
    }

    return true;
  }

  std::unique_ptr<sherpa_mnn::cxx::OnlineRecognizer> streaming_recognizer_;
  std::unique_ptr<sherpa_mnn::cxx::OfflineRecognizer>
      offline_whisper_recognizer_;
  RecognizerMode mode_ = RecognizerMode::kNone;
  std::string backend_name_;
  bool rnnoise_enabled_ = true;
};

SherpaMnnAsr::SherpaMnnAsr(bool rnnoise_enabled)
    : impl_(std::make_unique<Impl>(rnnoise_enabled)) {}

SherpaMnnAsr::~SherpaMnnAsr() = default;

bool SherpaMnnAsr::load(const std::string &model_dir, std::string &error) {
  return impl_->load(model_dir, error);
}

bool SherpaMnnAsr::transcribeFile(const std::string &wav_path, std::string &text,
                                 std::string &error,
                                 const AsrPartialCallback &partial_callback) {
  return impl_->transcribeFile(wav_path, text, error, partial_callback);
}

std::string SherpaMnnAsr::backendName() const { return impl_->backendName(); }

} // namespace edgemind