#include "asr_recognizer.h"

#include <sstream>
#include <sys/stat.h>
#include <vector>

#ifdef EDGEMIND_SHERPA_MNN_ASR_AVAILABLE
#include "sherpa_mnn_asr.h"
#endif

namespace edgemind {
namespace {

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

bool hasAllFiles(const std::string &model_dir,
                 const std::vector<std::string> &files) {
  for (const auto &file : files) {
    if (!pathExists(joinPath(model_dir, file))) {
      return false;
    }
  }

  return true;
}

std::string joinMessages(const std::vector<std::string> &messages) {
  std::ostringstream stream;
  for (size_t index = 0; index < messages.size(); ++index) {
    if (index != 0) {
      stream << " | ";
    }
    stream << messages[index];
  }
  return stream.str();
}

template <typename Recognizer>
std::unique_ptr<AsrRecognizer> tryLoadRecognizer(const std::string &model_dir,
                                                 bool rnnoise_enabled,
                                                 std::string &selected_backend,
                                                 std::string &error) {
  auto recognizer = std::make_unique<Recognizer>(rnnoise_enabled);
  if (!recognizer->load(model_dir, error)) {
    return nullptr;
  }

  selected_backend = recognizer->backendName();
  return recognizer;
}

} // namespace

std::unique_ptr<AsrRecognizer>
createAsrRecognizer(const std::string &model_dir, std::string &selected_backend,
                    std::string &error, bool rnnoise_enabled) {
  const bool has_streaming_sherpa_bundle = hasAllFiles(
      model_dir,
      {"config.json", "encoder-epoch-99-avg-1.mnn",
       "decoder-epoch-99-avg-1.mnn", "joiner-epoch-99-avg-1.mnn",
       "tokens.txt"});
  const bool has_whisper_bundle =
      hasAllFiles(model_dir, {"encode.mnn", "decode.mnn"}) &&
      (pathExists(joinPath(model_dir, "base-tokens.txt")) ||
       pathExists(joinPath(model_dir, "tiny.en-tokens.txt")));

  std::vector<std::string> load_errors;

#ifdef EDGEMIND_SHERPA_MNN_ASR_AVAILABLE
  if (has_streaming_sherpa_bundle || has_whisper_bundle) {
    std::string sherpa_error;
    auto recognizer =
      tryLoadRecognizer<SherpaMnnAsr>(model_dir, rnnoise_enabled,
                      selected_backend,
                                        sherpa_error);
    if (recognizer) {
      return recognizer;
    }

    if (!sherpa_error.empty()) {
      load_errors.push_back("sherpa-mnn: " + sherpa_error);
    }
  }
#endif

  if (!load_errors.empty()) {
    error = joinMessages(load_errors);
  } else {
    error = "No supported ASR model bundle found in " + model_dir +
            ". Expected either a sherpa-mnn streaming bundle or a Whisper-MNN bundle.";
  }

  return nullptr;
}

} // namespace edgemind