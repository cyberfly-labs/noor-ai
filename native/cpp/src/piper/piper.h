// Piper TTS - VITS Neural TTS with NCNN
// Based on nihui/ncnn-android-piper (BSD 3-Clause)
// Adapted for EdgeMind: file-path based loading, no AAssetManager

#ifndef PIPER_H
#define PIPER_H

#include <vector>
#include <string>
#include <net.h>

#include "simpleg2p.h"

class Piper
{
public:
    int load(const char* model_dir, const char* lang, bool use_gpu = false);

    void synthesize(const char* text, int speaker_id, float noise_scale,
                    float length_scale, float noise_scale_w,
                    std::vector<short>& pcm);

    int sampleRate() const { return 22050; }

protected:
    void path_attention(const ncnn::Mat& logw, const ncnn::Mat& m_p,
                        const ncnn::Mat& logs_p, float noise_scale,
                        float length_scale, ncnn::Mat& z_p);

protected:
    SimpleG2P g2p;
    bool has_multi_speakers = false;
    ncnn::Net emb_g;
    ncnn::Net enc_p;
    ncnn::Net dp;
    ncnn::Net flow;
    ncnn::Net dec;
};

#endif // PIPER_H
