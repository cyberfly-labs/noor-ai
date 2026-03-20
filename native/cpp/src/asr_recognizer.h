#ifndef EDGEMIND_ASR_RECOGNIZER_H
#define EDGEMIND_ASR_RECOGNIZER_H

#include <functional>
#include <memory>
#include <string>

namespace edgemind {

using AsrPartialCallback =
    std::function<void(const std::string &text, bool is_final)>;

class AsrRecognizer {
public:
  virtual ~AsrRecognizer() = default;

  virtual bool load(const std::string &model_dir, std::string &error) = 0;

  virtual bool transcribeFile(
      const std::string &wav_path, std::string &text, std::string &error,
      const AsrPartialCallback &partial_callback = AsrPartialCallback()) = 0;

  virtual std::string backendName() const = 0;
};

std::unique_ptr<AsrRecognizer>
createAsrRecognizer(const std::string &model_dir, std::string &selected_backend,
                    std::string &error, bool rnnoise_enabled = true);

} // namespace edgemind

#endif // EDGEMIND_ASR_RECOGNIZER_H