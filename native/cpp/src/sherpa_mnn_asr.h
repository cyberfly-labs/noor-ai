#ifndef EDGEMIND_SHERPA_MNN_ASR_H
#define EDGEMIND_SHERPA_MNN_ASR_H

#include <memory>
#include <string>

#include "asr_recognizer.h"

namespace edgemind {

class SherpaMnnAsr final : public AsrRecognizer {
public:
  explicit SherpaMnnAsr(bool rnnoise_enabled = true);
  ~SherpaMnnAsr() override;

  SherpaMnnAsr(const SherpaMnnAsr &) = delete;
  SherpaMnnAsr &operator=(const SherpaMnnAsr &) = delete;

  bool load(const std::string &model_dir, std::string &error) override;

  bool transcribeFile(
      const std::string &wav_path, std::string &text, std::string &error,
      const AsrPartialCallback &partial_callback = AsrPartialCallback())
      override;

  std::string backendName() const override;

private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

} // namespace edgemind

#endif // EDGEMIND_SHERPA_MNN_ASR_H