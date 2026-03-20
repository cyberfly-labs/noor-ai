// Piper TTS - VITS Neural TTS with NCNN
// Based on nihui/ncnn-android-piper (BSD 3-Clause)
// Adapted for EdgeMind: file-path based loading, no AAssetManager

#include "piper.h"

#include <stdio.h>
#include <cmath>
#include <algorithm>
#include <cstdlib>

#include "mat.h"
#include "net.h"
#include "layer.h"
#include "platform.h"

// =============================================================================
// Custom NCNN layers required by Piper VITS models
// =============================================================================

class Flip : public ncnn::Layer
{
public:
    Flip()
    {
        one_blob_only = true;
    }

    virtual int load_param(const ncnn::ParamDict& pd)
    {
        axes = pd.get(0, ncnn::Mat());
        if (axes.w > 4)
            return -1;
        return 0;
    }

    virtual int forward(const ncnn::Mat& bottom_blob, ncnn::Mat& top_blob,
                        const ncnn::Option& opt) const
    {
        if (axes.empty())
        {
            top_blob = bottom_blob;
            return 0;
        }

        const int dims = bottom_blob.dims;
        const int w = bottom_blob.w;
        const int h = bottom_blob.h;
        const int d = bottom_blob.d;
        const int channels = bottom_blob.c;

        int axes_flag[4] = {0};
        bool flip_w = false, flip_h = false, flip_d = false, flip_c = false;
        {
            const int* axes_ptr = axes;
            for (int i = 0; i < axes.w; i++)
            {
                int axis = axes_ptr[i];
                if (axis < 0) axis += dims;
                axes_flag[axis] = 1;
            }

            if (dims == 1) { flip_w = true; }
            else if (dims == 2)
            {
                if (axes_flag[0] == 1) flip_h = true;
                if (axes_flag[1] == 1) flip_w = true;
            }
            else if (dims == 3)
            {
                if (axes_flag[0] == 1) flip_c = true;
                if (axes_flag[1] == 1) flip_h = true;
                if (axes_flag[2] == 1) flip_w = true;
            }
            else if (dims == 4)
            {
                if (axes_flag[0] == 1) flip_c = true;
                if (axes_flag[1] == 1) flip_d = true;
                if (axes_flag[2] == 1) flip_h = true;
                if (axes_flag[3] == 1) flip_w = true;
            }
        }

        top_blob.create_like(bottom_blob, opt.blob_allocator);
        if (top_blob.empty()) return -100;

        #pragma omp parallel for num_threads(opt.num_threads)
        for (int q = 0; q < channels; q++)
        {
            for (int z = 0; z < d; z++)
            {
                for (int i = 0; i < h; i++)
                {
                    int q2 = flip_c ? channels - 1 - q : q;
                    int z2 = flip_d ? d - 1 - z : z;
                    int i2 = flip_h ? h - 1 - i : i;
                    const float* ptr = bottom_blob.channel(q2).depth(z2).row(i2);
                    float* outptr = top_blob.channel(q).depth(z).row(i);
                    if (flip_w)
                    {
                        ptr += w - 1;
                        for (int j = 0; j < w; j++)
                            *outptr++ = *ptr--;
                    }
                    else
                    {
                        memcpy(outptr, ptr, w * sizeof(float));
                    }
                }
            }
        }
        return 0;
    }

public:
    ncnn::Mat axes;
};

DEFINE_LAYER_CREATOR(Flip)

class relative_embeddings_k_module : public ncnn::Layer
{
public:
    relative_embeddings_k_module() { one_blob_only = true; }

    virtual int forward(const ncnn::Mat& bottom_blob, ncnn::Mat& top_blob,
                        const ncnn::Option& opt) const
    {
        const int window_size = 4;
        const int wsize = bottom_blob.w;
        const int len = bottom_blob.h;
        const int num_heads = bottom_blob.c;

        top_blob.create(len, len, num_heads);
        top_blob.fill(0.f);

        #pragma omp parallel for num_threads(opt.num_threads)
        for (int q = 0; q < num_heads; q++)
        {
            const ncnn::Mat x0 = bottom_blob.channel(q);
            ncnn::Mat out0 = top_blob.channel(q);
            for (int i = 0; i < len; i++)
            {
                const float* xptr = x0.row(i) + std::max(0, window_size - i);
                float* outptr = out0.row(i) + std::max(i - window_size, 0);
                const int wsize2 = std::min(len, i - window_size + wsize) - std::max(i - window_size, 0);
                for (int j = 0; j < wsize2; j++)
                    *outptr++ = *xptr++;
            }
        }
        return 0;
    }
};

DEFINE_LAYER_CREATOR(relative_embeddings_k_module)

class relative_embeddings_v_module : public ncnn::Layer
{
public:
    relative_embeddings_v_module() { one_blob_only = true; }

    virtual int forward(const ncnn::Mat& bottom_blob, ncnn::Mat& top_blob,
                        const ncnn::Option& opt) const
    {
        const int window_size = 4;
        const int wsize = window_size * 2 + 1;
        const int len = bottom_blob.h;
        const int num_heads = bottom_blob.c;

        top_blob.create(wsize, len, num_heads);
        top_blob.fill(0.f);

        #pragma omp parallel for num_threads(opt.num_threads)
        for (int q = 0; q < num_heads; q++)
        {
            const ncnn::Mat x0 = bottom_blob.channel(q);
            ncnn::Mat out0 = top_blob.channel(q);
            for (int i = 0; i < len; i++)
            {
                const float* xptr = x0.row(i) + std::max(i - window_size, 0);
                float* outptr = out0.row(i) + std::max(0, window_size - i);
                const int wsize2 = std::min(len, i - window_size + wsize) - std::max(i - window_size, 0);
                for (int j = 0; j < wsize2; j++)
                    *outptr++ = *xptr++;
            }
        }
        return 0;
    }
};

DEFINE_LAYER_CREATOR(relative_embeddings_v_module)

class piecewise_rational_quadratic_transform_module : public ncnn::Layer
{
public:
    piecewise_rational_quadratic_transform_module() { one_blob_only = false; }

    virtual int forward(const std::vector<ncnn::Mat>& bottom_blobs,
                        std::vector<ncnn::Mat>& top_blobs,
                        const ncnn::Option& opt) const
    {
        const ncnn::Mat& h = bottom_blobs[0];
        const ncnn::Mat& x1 = bottom_blobs[1];
        ncnn::Mat& outputs = top_blobs[0];

        const int num_bins = 10;
        const int filter_channels = 192;
        const bool reverse = true;
        const float tail_bound = 5.0f;
        const float DEFAULT_MIN_BIN_WIDTH = 1e-3f;
        const float DEFAULT_MIN_BIN_HEIGHT = 1e-3f;
        const float DEFAULT_MIN_DERIVATIVE = 1e-3f;

        const int batch_size = x1.w;

        outputs = x1.clone();
        float* out_ptr = outputs;

        #pragma omp parallel for num_threads(opt.num_threads)
        for (int i = 0; i < batch_size; ++i)
        {
            const float current_x = ((const float*)x1)[i];
            const float* h_data = h.row(i);

            if (current_x < -tail_bound || current_x > tail_bound)
                continue;

            std::vector<float> unnormalized_widths(num_bins);
            std::vector<float> unnormalized_heights(num_bins);
            std::vector<float> unnormalized_derivatives(num_bins + 1);

            const float inv_sqrt = 1.0f / sqrtf(filter_channels);
            for (int j = 0; j < num_bins; ++j)
                unnormalized_widths[j] = h_data[j] * inv_sqrt;
            for (int j = 0; j < num_bins; ++j)
                unnormalized_heights[j] = h_data[num_bins + j] * inv_sqrt;
            for (int j = 0; j < num_bins - 1; ++j)
                unnormalized_derivatives[j + 1] = h_data[2 * num_bins + j];

            const float constant = logf(expf(1.f - DEFAULT_MIN_DERIVATIVE) - 1.f);
            unnormalized_derivatives[0] = constant;
            unnormalized_derivatives[num_bins] = constant;

            const float left = -tail_bound, right = tail_bound;
            const float bottom = -tail_bound, top = tail_bound;

            // Softmax + Affine for widths
            std::vector<float> widths(num_bins);
            float w_max = -INFINITY;
            for (float val : unnormalized_widths) w_max = std::max(w_max, val);
            float w_sum = 0.f;
            for (int j = 0; j < num_bins; ++j)
            {
                widths[j] = expf(unnormalized_widths[j] - w_max);
                w_sum += widths[j];
            }
            for (int j = 0; j < num_bins; ++j)
                widths[j] = DEFAULT_MIN_BIN_WIDTH + (1.f - DEFAULT_MIN_BIN_WIDTH * num_bins) * (widths[j] / w_sum);

            std::vector<float> cumwidths(num_bins + 1);
            cumwidths[0] = left;
            float current_w_sum = 0.f;
            for (int j = 0; j < num_bins - 1; ++j)
            {
                current_w_sum += widths[j];
                cumwidths[j + 1] = left + (right - left) * current_w_sum;
            }
            cumwidths[num_bins] = right;

            // Heights
            std::vector<float> heights(num_bins);
            float h_max = -INFINITY;
            for (float val : unnormalized_heights) h_max = std::max(h_max, val);
            float h_sum = 0.f;
            for (int j = 0; j < num_bins; ++j)
            {
                heights[j] = expf(unnormalized_heights[j] - h_max);
                h_sum += heights[j];
            }
            for (int j = 0; j < num_bins; ++j)
                heights[j] = DEFAULT_MIN_BIN_HEIGHT + (1.f - DEFAULT_MIN_BIN_HEIGHT * num_bins) * (heights[j] / h_sum);

            std::vector<float> cumheights(num_bins + 1);
            cumheights[0] = bottom;
            float current_h_sum = 0.f;
            for (int j = 0; j < num_bins - 1; ++j)
            {
                current_h_sum += heights[j];
                cumheights[j + 1] = bottom + (top - bottom) * current_h_sum;
            }
            cumheights[num_bins] = top;

            // Softplus for derivatives
            std::vector<float> derivatives(num_bins + 1);
            for (int j = 0; j < num_bins + 1; ++j)
            {
                float x = unnormalized_derivatives[j];
                derivatives[j] = DEFAULT_MIN_DERIVATIVE + (x > 0 ? x + logf(1.f + expf(-x)) : logf(1.f + expf(x)));
            }

            // Find bin
            int bin_idx = 0;
            if (reverse)
            {
                auto it = std::upper_bound(cumheights.begin(), cumheights.end(), current_x);
                bin_idx = std::distance(cumheights.begin(), it) - 1;
            }
            else
            {
                auto it = std::upper_bound(cumwidths.begin(), cumwidths.end(), current_x);
                bin_idx = std::distance(cumwidths.begin(), it) - 1;
            }
            bin_idx = std::max(0, std::min(bin_idx, num_bins - 1));

            const float input_cumwidths = cumwidths[bin_idx];
            const float input_bin_widths = cumwidths[bin_idx + 1] - cumwidths[bin_idx];
            const float input_cumheights = cumheights[bin_idx];
            const float input_heights = cumheights[bin_idx + 1] - cumheights[bin_idx];
            const float input_derivatives = derivatives[bin_idx];
            const float input_derivatives_plus_one = derivatives[bin_idx + 1];
            const float delta = input_heights / input_bin_widths;

            if (reverse)
            {
                float a = (current_x - input_cumheights) * (input_derivatives + input_derivatives_plus_one - 2 * delta)
                        + input_heights * (delta - input_derivatives);
                float b = input_heights * input_derivatives
                        - (current_x - input_cumheights) * (input_derivatives + input_derivatives_plus_one - 2 * delta);
                float c = -delta * (current_x - input_cumheights);
                float discriminant = std::max(0.f, b * b - 4 * a * c);
                float root = (2 * c) / (-b - sqrtf(discriminant));
                out_ptr[i] = root * input_bin_widths + input_cumwidths;
            }
            else
            {
                float theta = (current_x - input_cumwidths) / input_bin_widths;
                float theta_one_minus_theta = theta * (1 - theta);
                float numerator = input_heights * (delta * theta * theta + input_derivatives * theta_one_minus_theta);
                float denominator = delta + ((input_derivatives + input_derivatives_plus_one - 2 * delta) * theta_one_minus_theta);
                out_ptr[i] = input_cumheights + numerator / denominator;
            }
        }
        return 0;
    }
};

DEFINE_LAYER_CREATOR(piecewise_rational_quadratic_transform_module)

// =============================================================================
// Piper class implementation
// =============================================================================

int Piper::load(const char* model_dir, const char* lang, bool use_gpu)
{
    g2p.clear();
    emb_g.clear();
    enc_p.clear();
    dp.clear();
    flow.clear();
    dec.clear();

#if NCNN_VULKAN
    emb_g.opt.use_vulkan_compute = use_gpu;
    enc_p.opt.use_vulkan_compute = use_gpu;
    dp.opt.use_vulkan_compute = use_gpu;
    flow.opt.use_vulkan_compute = use_gpu;
    dec.opt.use_vulkan_compute = use_gpu;
#endif

    std::string dir(model_dir);
    if (!dir.empty() && dir.back() != '/')
        dir += '/';

    std::string enc_param = dir + lang + std::string("_enc_p.ncnn.param");
    std::string enc_bin   = dir + lang + std::string("_enc_p.ncnn.bin");
    std::string dp_param  = dir + lang + std::string("_dp.ncnn.param");
    std::string dp_bin    = dir + lang + std::string("_dp.ncnn.bin");
    std::string flow_param = dir + lang + std::string("_flow.ncnn.param");
    std::string flow_bin   = dir + lang + std::string("_flow.ncnn.bin");
    std::string dec_param  = dir + lang + std::string("_dec.ncnn.param");
    std::string dec_bin    = dir + lang + std::string("_dec.ncnn.bin");
    std::string emb_param  = dir + lang + std::string("_emb_g.ncnn.param");
    std::string emb_bin    = dir + lang + std::string("_emb_g.ncnn.bin");

    // Register custom layers (Flip is built-in since ncnn 1.0.20250806)
#if defined(NCNN_VERSION_STRING)
    if (atoi(NCNN_VERSION_STRING + 4) < 20250806)
#endif
    {
        dp.register_custom_layer("Flip", Flip_layer_creator);
        flow.register_custom_layer("Flip", Flip_layer_creator);
    }

    enc_p.register_custom_layer(
        "piper.train.vits.attentions.relative_embeddings_k_module",
        relative_embeddings_k_module_layer_creator);
    enc_p.register_custom_layer(
        "piper.train.vits.attentions.relative_embeddings_v_module",
        relative_embeddings_v_module_layer_creator);
    dp.register_custom_layer(
        "piper.train.vits.modules.piecewise_rational_quadratic_transform_module",
        piecewise_rational_quadratic_transform_module_layer_creator);

    // Load G2P dictionary
    std::string g2p_lang = dir + lang;
    g2p.load(g2p_lang.c_str());

    enc_p.load_param(enc_param.c_str());
    enc_p.load_model(enc_bin.c_str());

    dp.load_param(dp_param.c_str());
    dp.load_model(dp_bin.c_str());

    flow.load_param(flow_param.c_str());
    flow.load_model(flow_bin.c_str());

    dec.load_param(dec_param.c_str());
    dec.load_model(dec_bin.c_str());

    has_multi_speakers = dec.input_indexes().size() == 2;

    if (has_multi_speakers)
    {
        emb_g.load_param(emb_param.c_str());
        emb_g.load_model(emb_bin.c_str());
    }

    return 0;
}

void Piper::synthesize(const char* text, int speaker_id,
                       float noise_scale, float length_scale,
                       float noise_scale_w, std::vector<short>& pcm)
{
    // Phonemize
    ncnn::Mat sequence;
    {
        std::vector<int> sequence_ids;
        g2p.phonemize(text, sequence_ids);
        const int sequence_length = (int)sequence_ids.size();
        sequence.create(sequence_length);
        memcpy(sequence, sequence_ids.data(), sequence_length * sizeof(int));
    }

    // enc_p
    ncnn::Mat x, m_p, logs_p;
    {
        ncnn::Extractor ex = enc_p.create_extractor();
        ex.input("in0", sequence);
        ex.extract("out0", x);
        ex.extract("out1", m_p);
        ex.extract("out2", logs_p);
    }

    // emb_g (multi-speaker)
    ncnn::Mat g;
    if (has_multi_speakers)
    {
        ncnn::Mat speaker_id_mat(1);
        {
            int* p = speaker_id_mat;
            p[0] = speaker_id;
        }
        ncnn::Extractor ex = emb_g.create_extractor();
        ex.input("in0", speaker_id_mat);
        ex.extract("out0", g);
        g = g.reshape(1, g.w);
    }

    // dp (duration predictor)
    ncnn::Mat logw;
    {
        ncnn::Mat noise(x.w, 2);
        for (int i = 0; i < noise.w * noise.h; i++)
            noise[i] = rand() / (float)RAND_MAX * noise_scale_w;

        ncnn::Extractor ex = dp.create_extractor();
        ex.input("in0", x);
        ex.input("in1", noise);
        if (has_multi_speakers) ex.input("in2", g);
        ex.extract("out0", logw);
    }

    // Path attention
    ncnn::Mat z_p;
    path_attention(logw, m_p, logs_p, noise_scale, length_scale, z_p);

    // flow
    ncnn::Mat z;
    {
        ncnn::Extractor ex = flow.create_extractor();
        ex.input("in0", z_p);
        if (has_multi_speakers) ex.input("in1", g);
        ex.extract("out0", z);
    }

    // dec (decoder)
    ncnn::Mat o;
    {
        ncnn::Extractor ex = dec.create_extractor();
        ex.input("in0", z);
        if (has_multi_speakers) ex.input("in1", g);
        ex.extract("out0", o);
    }

    // Normalize and clip
    {
        float absmax = 0.f;
        for (int i = 0; i < o.w; i++)
            absmax = std::max(absmax, fabsf(o[i]));

        if (absmax > 1e-8)
        {
            for (int i = 0; i < o.w; i++)
            {
                float v = o[i] / absmax;
                v = std::min(std::max(v, -1.f), 1.f);
                o[i] = v;
            }
        }
    }

    // Convert to 16-bit PCM
    pcm.resize(o.w);
    for (int i = 0; i < o.w; i++)
        pcm[i] = (short)(o[i] * 32767);
}

void Piper::path_attention(const ncnn::Mat& logw, const ncnn::Mat& m_p,
                           const ncnn::Mat& logs_p, float noise_scale,
                           float length_scale, ncnn::Mat& z_p)
{
    const int x_lengths = logw.w;
    const int depth = m_p.h;

    std::vector<int> w_ceil(x_lengths);
    int y_lengths = 0;
    for (int i = 0; i < x_lengths; i++)
    {
        w_ceil[i] = (int)ceilf(expf(logw[i]) * length_scale);
        y_lengths += w_ceil[i];
    }

    z_p.create(y_lengths, depth);

    for (int i = 0; i < depth; i++)
    {
        const float* m_p_ptr = m_p.row(i);
        const float* logs_p_ptr = logs_p.row(i);
        float* ptr = z_p.row(i);

        for (int j = 0; j < x_lengths; j++)
        {
            const float m = m_p_ptr[j];
            const float nl = expf(logs_p_ptr[j]) * noise_scale;
            const int duration = w_ceil[j];

            for (int k = 0; k < duration; k++)
                ptr[k] = m + (rand() / (float)RAND_MAX) * nl;

            ptr += duration;
        }
    }
}
