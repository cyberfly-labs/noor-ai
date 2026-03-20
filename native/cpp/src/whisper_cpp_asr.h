#ifndef EDGEMIND_WHISPER_CPP_ASR_H
#define EDGEMIND_WHISPER_CPP_ASR_H

#include <functional>
#include <string>

struct whisper_context;

namespace edgemind {

using WhisperPartialCallback =
  std::function<void(const std::string &text, bool is_final)>;

class WhisperCppAsr {
public:
  WhisperCppAsr();
  ~WhisperCppAsr();

  WhisperCppAsr(const WhisperCppAsr &) = delete;
  WhisperCppAsr &operator=(const WhisperCppAsr &) = delete;

  bool load(const std::string &model_dir_or_file, std::string &error);
  bool transcribeFile(const std::string &wav_path, std::string &text,
            std::string &error,
            const WhisperPartialCallback &partial_callback =
              WhisperPartialCallback());

private:
  void reset();

  whisper_context *context_ = nullptr;
  std::string model_path_;
};

} // namespace edgemind

#endif // EDGEMIND_WHISPER_CPP_ASR_H