// Supertonic TTS - Diffusion-based Neural TTS with MNN
// Based on supertonic-mnn by yunfengwang (OpenRAIL License)
// C++ port for EdgeMind on-device inference

#ifndef SUPERTONIC_TTS_H
#define SUPERTONIC_TTS_H

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include <MNN/expr/Executor.hpp>
#include <MNN/expr/Module.hpp>

class SupertonicTTS {
public:
  SupertonicTTS();
  ~SupertonicTTS();

  /// Load models from the given directory.
  /// model_dir should contain: mnn_models/int8/*.mnn, mnn_models/tts.json,
  ///   mnn_models/unicode_indexer.json, voice_styles/*.json
  /// Returns 0 on success, negative on error.
  int load(const char *model_dir, const char *voice = "F1",
           int num_threads = 4);

  /// Synthesize speech from text.
  /// Output: interleaved float32 PCM samples at sampleRate().
  void synthesize(const char *text, float speed, int denoise_steps,
                  std::vector<float> &pcm_out);

  int sampleRate() const { return sample_rate_; }

private:
  // MNN models
  std::shared_ptr<MNN::Express::Module> dp_model_;
  std::shared_ptr<MNN::Express::Module> text_enc_model_;
  std::shared_ptr<MNN::Express::Module> vector_est_model_;
  std::shared_ptr<MNN::Express::Module> vocoder_model_;

  // Runtime manager shared across all models
  std::shared_ptr<MNN::Express::Executor::RuntimeManager> rt_manager_;

  // Unicode indexer: unicode code point → token index
  std::unordered_map<int, int> unicode_indexer_;

  // Voice style data
  std::vector<float> style_ttl_;
  std::vector<int> style_ttl_dims_; // [1, dim1, dim2]
  std::vector<float> style_dp_;
  std::vector<int> style_dp_dims_; // [1, dim1, dim2]

  // Model config from tts.json
  int sample_rate_ = 44100;
  int base_chunk_size_ = 512;
  int latent_dim_ = 24;
  int chunk_compress_factor_ = 6; // from ttl config

  bool loaded_ = false;
};

#endif // SUPERTONIC_TTS_H
