#include "main.h"
#include "whisper.h"

#define DR_WAV_IMPLEMENTATION
#include "whisper.cpp/examples/dr_wav.h"

#include <cstdio>
#include <string>
#include <thread>
#include <vector>
#include <cmath>
#include <cerrno>
#include <iostream>
#include <stdio.h>
#include <mutex>
#include "json/json.hpp"

using json = nlohmann::json;

// Capture whisper native log output for diagnostics
static std::string g_log_buffer;
static std::mutex g_log_mutex;

static void whisper_log_callback(enum ggml_log_level level, const char * text, void * user_data) {
    (void)user_data;
    (void)level;
    fprintf(stderr, "[whisper] %s", text);
    std::lock_guard<std::mutex> lock(g_log_mutex);
    g_log_buffer += text;
    // Keep only last 2K to avoid unbounded growth
    if (g_log_buffer.size() > 2048) {
        g_log_buffer = g_log_buffer.substr(g_log_buffer.size() - 2048);
    }
}

char *jsonToChar(json jsonData) noexcept
{
    std::string result = jsonData.dump();
    char *ch = new char[result.size() + 1];
    strcpy(ch, result.c_str());
    return ch;
}

struct whisper_params
{
    int32_t seed = -1; // RNG seed, not used currently
    int32_t n_threads = std::min(4, (int32_t)std::thread::hardware_concurrency());

    int32_t n_processors = 1;
    int32_t offset_t_ms = 0;
    int32_t offset_n = 0;
    int32_t duration_ms = 0;
    int32_t max_context = -1;
    int32_t max_len = 0;
    int32_t best_of = 5;
    int32_t beam_size = -1;

    float word_thold = 0.01f;
    float entropy_thold = 2.40f;
    float logprob_thold = -1.00f;

    bool verbose = false;
    bool print_special_tokens = false;
    bool speed_up = false;
    bool translate = false;
    bool diarize = false;
    bool no_fallback = false;
    bool output_txt = false;
    bool output_vtt = false;
    bool output_srt = false;
    bool output_wts = false;
    bool output_csv = false;
    bool print_special = false;
    bool print_colors = false;
    bool print_progress = false;
    bool no_timestamps = false;
    bool split_on_word = false;

    std::string language = "auto";
    std::string prompt;
    std::string model = "models/ggml-tiny.bin";
    std::string audio = "samples/jfk.wav";
    std::vector<std::string> fname_inp = {};
    std::vector<std::string> fname_outp = {};
};

struct whisper_print_user_data
{
    const whisper_params *params;

    const std::vector<std::vector<float>> *pcmf32s;
};

json transcribe(json jsonBody) noexcept
{
    whisper_params params;

    params.n_threads = jsonBody["threads"];
    params.verbose = jsonBody["is_verbose"];
    params.translate = jsonBody["is_translate"];
    params.language = jsonBody["language"];
    params.print_special_tokens = jsonBody["is_special_tokens"];
    params.no_timestamps = jsonBody["is_no_timestamps"];
    params.model = jsonBody["model"];
    params.audio = jsonBody["audio"];
    params.split_on_word = jsonBody["split_on_word"];
    json jsonResult;
    jsonResult["@type"] = "transcribe";

    if (params.language != "" && params.language != "auto" && whisper_lang_id(params.language.c_str()) == -1)
    {
        jsonResult["@type"] = "error";
        jsonResult["message"] = "error: unknown language = " + params.language;
        return jsonResult;
    }

    if (params.seed < 0)
    {
        params.seed = time(NULL);
    }

    // whisper init — set log callback to capture diagnostics
    whisper_log_set(whisper_log_callback, nullptr);
    {
        std::lock_guard<std::mutex> lock(g_log_mutex);
        g_log_buffer.clear();
    }
    
    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false; // CPU-only on mobile
    cparams.flash_attn = false; // Not useful without GPU
    fprintf(stderr, "[whisper-ffi] Loading model: %s\n", params.model.c_str());
    
    // Verify file exists and is readable
    FILE* ftest = fopen(params.model.c_str(), "rb");
    if (!ftest) {
        jsonResult["@type"] = "error";
        jsonResult["message"] = "model file not accessible: " + params.model + " (errno=" + std::to_string(errno) + ")";
        return jsonResult;
    }
    fseek(ftest, 0, SEEK_END);
    long fsize = ftell(ftest);
    // Read first 4 bytes to check magic
    fseek(ftest, 0, SEEK_SET);
    uint32_t magic = 0;
    fread(&magic, 4, 1, ftest);
    fclose(ftest);
    fprintf(stderr, "[whisper-ffi] Model file size: %ld bytes, magic: 0x%08x\n", fsize, magic);
    
    struct whisper_context *ctx = whisper_init_from_file_with_params(params.model.c_str(), cparams);
    fprintf(stderr, "[whisper-ffi] Model init result: %s\n", ctx ? "success" : "NULL");
    if (ctx == nullptr)
    {
        std::string log_capture;
        {
            std::lock_guard<std::mutex> lock(g_log_mutex);
            log_capture = g_log_buffer;
        }
        jsonResult["@type"] = "error";
        jsonResult["message"] = "failed to initialize whisper model from: " + params.model + 
            " (size=" + std::to_string(fsize) + ", magic=0x" + 
            ([&]() { char buf[16]; snprintf(buf, sizeof(buf), "%08x", magic); return std::string(buf); })() +
            ") native_log: " + log_capture;
        return jsonResult;
    }
    std::string text_result = "";
    const auto fname_inp = params.audio;
    // WAV input
    std::vector<float> pcmf32;
    {
        drwav wav;
        if (!drwav_init_file(&wav, fname_inp.c_str(), NULL))
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = " failed to open WAV file ";
            return jsonResult;
        }

        if (wav.channels != 1 && wav.channels != 2)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "must be mono or stereo";
            return jsonResult;
        }

        if (wav.bitsPerSample != 16)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV file must be 16 bit";
            return jsonResult;
        }

        const uint32_t src_rate = wav.sampleRate;
        int n = wav.totalPCMFrameCount;

        std::vector<int16_t> pcm16;
        pcm16.resize(n * wav.channels);
        drwav_read_pcm_frames_s16(&wav, n, pcm16.data());
        drwav_uninit(&wav);

        // convert to mono, float
        pcmf32.resize(n);
        if (wav.channels == 1)
        {
            for (int i = 0; i < n; i++)
            {
                pcmf32[i] = float(pcm16[i]) / 32768.0f;
            }
        }
        else
        {
            for (int i = 0; i < n; i++)
            {
                pcmf32[i] = float(pcm16[2 * i] + pcm16[2 * i + 1]) / 65536.0f;
            }
        }

        // Resample to 16kHz if needed (AFTER reading data)
        if (src_rate != WHISPER_SAMPLE_RATE)
        {
            const int dst_rate = WHISPER_SAMPLE_RATE;
            const int n_src = (int)pcmf32.size();
            const double ratio = (double)src_rate / (double)dst_rate;
            const int n_dst = (int)((double)n_src / ratio);

            fprintf(stderr, "[whisper-ffi] Resampling %d→%dHz (%d→%d samples)\n",
                    src_rate, dst_rate, n_src, n_dst);

            std::vector<float> resampled(n_dst);
            for (int i = 0; i < n_dst; i++) {
                double src_pos = i * ratio;
                int idx = (int)src_pos;
                double frac = src_pos - idx;
                if (idx + 1 < n_src) {
                    resampled[i] = pcmf32[idx] * (1.0f - (float)frac) + pcmf32[idx + 1] * (float)frac;
                } else if (idx < n_src) {
                    resampled[i] = pcmf32[idx];
                }
            }
            pcmf32 = std::move(resampled);
        }
    }

    {
        if (params.language == "" && params.language == "auto")
        {
            params.language = "auto";
            params.translate = false;
        }
    }
    // run the inference
    {
        whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

        wparams.print_realtime = false;
        wparams.print_progress = false;
        wparams.print_timestamps = !params.no_timestamps;
        // wparams.print_special_tokens = params.print_special_tokens;
        wparams.translate = params.translate;
        wparams.language = params.language.c_str();
        wparams.n_threads = params.n_threads;
        wparams.split_on_word = params.split_on_word;

        if (params.split_on_word) {
            wparams.max_len = 1;
            wparams.token_timestamps = true;
        }

        if (whisper_full(ctx, wparams, pcmf32.data(), pcmf32.size()) != 0)
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = "failed to process audio";
            return jsonResult;
        }

        

        // print result;
        if (!wparams.print_realtime)
        {

            const int n_segments = whisper_full_n_segments(ctx);

            std::vector<json> segmentsJson = {};

            for (int i = 0; i < n_segments; ++i)
            {
                const char *text = whisper_full_get_segment_text(ctx, i);

                std::string str(text);
                text_result += str;
                if (params.no_timestamps)
                {
                    // printf("%s", text);
                    // fflush(stdout);
                } else {
                    json jsonSegment;
                    const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
                    const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

                    // printf("[%s --> %s]  %s\n", to_timestamp(t0).c_str(), to_timestamp(t1).c_str(), text);

                    jsonSegment["from_ts"] = t0;
                    jsonSegment["to_ts"] = t1;
                    jsonSegment["text"] = text;

                    segmentsJson.push_back(jsonSegment);
                }
            }

            if (!params.no_timestamps) {
                jsonResult["segments"] = segmentsJson;
            }
        }
    }
    jsonResult["text"] = text_result;
    
    whisper_free(ctx);
    return jsonResult;
}
extern "C"
{
    FUNCTION_ATTRIBUTE
    char *request(char *body)
    {
        try
        {
            json jsonBody = json::parse(body);
            json jsonResult;

            if (jsonBody["@type"] == "getTextFromWavFile")
            {
                try
                {
                    return jsonToChar(transcribe(jsonBody));
                }
                catch (const std::exception &e)
                {
                    jsonResult["@type"] = "error";
                    jsonResult["message"] = e.what();
                    return jsonToChar(jsonResult);
                }
            }
            if (jsonBody["@type"] == "getVersion")
            {
                jsonResult["@type"] = "version";
                jsonResult["message"] = "lib version: v1.0.1";
                return jsonToChar(jsonResult);
            }

            jsonResult["@type"] = "error";
            jsonResult["message"] = "method not found";
            return jsonToChar(jsonResult);
        }
        catch (const std::exception &e)
        {
            json jsonResult;
            jsonResult["@type"] = "error";
            jsonResult["message"] = e.what();
            return jsonToChar(jsonResult);
        }
    }
}