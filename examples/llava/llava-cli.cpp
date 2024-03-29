#include "ggml.h"
#include "common.h"
#include "clip.h"
#include "llava.h"
#include "moses.h"

#include "base64.hpp"

#include <cstdio>
#include <cstdlib>
#include <vector>

static bool eval_tokens(struct moses_context * ctx_moses, std::vector<moses_token> tokens, int n_batch, int * n_past) {
    int N = (int) tokens.size();
    for (int i = 0; i < N; i += n_batch) {
        int n_eval = (int) tokens.size() - i;
        if (n_eval > n_batch) {
            n_eval = n_batch;
        }
        if (moses_decode(ctx_moses, moses_batch_get_one(&tokens[i], n_eval, *n_past, 0))) {
            fprintf(stderr, "%s : failed to eval. token %d/%d (batch size %d, n_past %d)\n", __func__, i, N, n_batch, *n_past);
            return false;
        }
        *n_past += n_eval;
    }
    return true;
}

static bool eval_id(struct moses_context * ctx_moses, int id, int * n_past) {
    std::vector<moses_token> tokens;
    tokens.push_back(id);
    return eval_tokens(ctx_moses, tokens, 1, n_past);
}

static bool eval_string(struct moses_context * ctx_moses, const char* str, int n_batch, int * n_past, bool add_bos){
    std::string              str2     = str;
    std::vector<moses_token> embd_inp = ::moses_tokenize(ctx_moses, str2, add_bos);
    eval_tokens(ctx_moses, embd_inp, n_batch, n_past);
    return true;
}

static const char * sample(struct moses_sampling_context * ctx_sampling,
                           struct moses_context * ctx_moses,
                           int * n_past) {
    const moses_token id = moses_sampling_sample(ctx_sampling, ctx_moses, NULL);
    moses_sampling_accept(ctx_sampling, ctx_moses, id, true);
    static std::string ret;
    if (id == moses_token_eos(moses_get_model(ctx_moses))) {
        ret = "</s>";
    } else {
        ret = moses_token_to_piece(ctx_moses, id);
    }
    eval_id(ctx_moses, id, n_past);
    return ret.c_str();
}

static const char* IMG_BASE64_TAG_BEGIN = "<img src=\"data:image/jpeg;base64,";
static const char* IMG_BASE64_TAG_END = "\">";

static void find_image_tag_in_prompt(const std::string& prompt, size_t& begin_out, size_t& end_out) {
    begin_out = prompt.find(IMG_BASE64_TAG_BEGIN);
    end_out = prompt.find(IMG_BASE64_TAG_END, (begin_out == std::string::npos) ? 0UL : begin_out);
}

static bool prompt_contains_image(const std::string& prompt) {
    size_t begin, end;
    find_image_tag_in_prompt(prompt, begin, end);
    return (begin != std::string::npos);
}

// replaces the base64 image tag in the prompt with `replacement`
static llava_image_embed * llava_image_embed_make_with_prompt_base64(struct clip_ctx * ctx_clip, int n_threads, const std::string& prompt) {
    size_t img_base64_str_start, img_base64_str_end;
    find_image_tag_in_prompt(prompt, img_base64_str_start, img_base64_str_end);
    if (img_base64_str_start == std::string::npos || img_base64_str_end == std::string::npos) {
        fprintf(stderr, "%s: invalid base64 image tag. must be %s<base64 byte string>%s\n", __func__, IMG_BASE64_TAG_BEGIN, IMG_BASE64_TAG_END);
        return NULL;
    }

    auto base64_bytes_start = img_base64_str_start + strlen(IMG_BASE64_TAG_BEGIN);
    auto base64_bytes_count = img_base64_str_end - base64_bytes_start;
    auto base64_str = prompt.substr(base64_bytes_start, base64_bytes_count );

    auto required_bytes = base64::required_encode_size(base64_str.size());
    auto img_bytes = std::vector<unsigned char>(required_bytes);
    base64::decode(base64_str.begin(), base64_str.end(), img_bytes.begin());

    auto embed = llava_image_embed_make_with_bytes(ctx_clip, n_threads, img_bytes.data(), img_bytes.size());
    if (!embed) {
        fprintf(stderr, "%s: could not load image from base64 string.\n", __func__);
        return NULL;
    }

    return embed;
}

static std::string remove_image_from_prompt(const std::string& prompt, const char * replacement = "") {
    size_t begin, end;
    find_image_tag_in_prompt(prompt, begin, end);
    if (begin == std::string::npos || end == std::string::npos) {
        return prompt;
    }
    auto pre = prompt.substr(0, begin);
    auto post = prompt.substr(end + strlen(IMG_BASE64_TAG_END));
    return pre + replacement + post;
}

struct llava_context {
    struct clip_ctx * ctx_clip = NULL;
    struct moses_context * ctx_moses = NULL;
    struct moses_model * model = NULL;
};

static void show_additional_info(int /*argc*/, char ** argv) {
    fprintf(stderr, "\n example usage: %s -m <llava-v1.5-7b/ggml-model-q5_k.gguf> --mmproj <llava-v1.5-7b/mmproj-model-f16.gguf> --image <path/to/an/image.jpg> [--temp 0.1] [-p \"describe the image in detail.\"]\n", argv[0]);
    fprintf(stderr, "  note: a lower temperature value like 0.1 is recommended for better quality.\n");
}

static struct llava_image_embed * load_image(llava_context * ctx_llava, gpt_params * params) {

    // load and preprocess the image
    llava_image_embed * embed = NULL;
    auto prompt = params->prompt;
    if (prompt_contains_image(prompt)) {
        if (!params->image.empty()) {
            fprintf(stderr, "using base64 encoded image instead of command line image path\n");
        }
        embed = llava_image_embed_make_with_prompt_base64(ctx_llava->ctx_clip, params->n_threads, prompt);
        if (!embed) {
            fprintf(stderr, "%s: can't load image from prompt\n", __func__);
            return NULL;
        }
        params->prompt = remove_image_from_prompt(prompt);
    } else {
        embed = llava_image_embed_make_with_filename(ctx_llava->ctx_clip, params->n_threads, params->image.c_str());
        if (!embed) {
            fprintf(stderr, "%s: is %s really an image file?\n", __func__, params->image.c_str());
            return NULL;
        }
    }

    return embed;
}

static void process_prompt(struct llava_context * ctx_llava, struct llava_image_embed * image_embed, gpt_params * params, const std::string & prompt) {
    int n_past = 0;

    const int max_tgt_len = params->n_predict < 0 ? 256 : params->n_predict;
    const bool add_bos = moses_should_add_bos_token(moses_get_model(ctx_llava->ctx_moses));

    std::string system_prompt, user_prompt;
    size_t image_pos = prompt.find("<image>");
    if (image_pos != std::string::npos) {
        // new templating mode: Provide the full prompt including system message and use <image> as a placeholder for the image

        system_prompt = prompt.substr(0, image_pos);
        user_prompt = prompt.substr(image_pos + std::string("<image>").length());
        // We replace \n with actual newlines in user_prompt, just in case -e was not used in templating string
        size_t pos = 0;
        while ((pos = user_prompt.find("\\n", pos)) != std::string::npos) {
            user_prompt.replace(pos, 2, "\n");
            pos += 1; // Advance past the replaced newline
        }
        while ((pos = system_prompt.find("\\n", pos)) != std::string::npos) {
            system_prompt.replace(pos, 2, "\n");
            pos += 1; // Advance past the replaced newline
        }

        printf("system_prompt: %s\n", system_prompt.c_str());
        printf("user_prompt: %s\n", user_prompt.c_str());
    } else {
        // llava-1.5 native mode
        system_prompt = "A chat between a curious human and an artificial intelligence assistant. The assistant gives helpful, detailed, and polite answers to the human's questions.\nUSER:";
        user_prompt = prompt + "\nASSISTANT:";
    }

    eval_string(ctx_llava->ctx_moses, system_prompt.c_str(), params->n_batch, &n_past, add_bos);
    llava_eval_image_embed(ctx_llava->ctx_moses, image_embed, params->n_batch, &n_past);
    eval_string(ctx_llava->ctx_moses, user_prompt.c_str(), params->n_batch, &n_past, false);

    // generate the response

    fprintf(stderr, "\n");

    struct moses_sampling_context * ctx_sampling = moses_sampling_init(params->sparams);

    for (int i = 0; i < max_tgt_len; i++) {
        const char * tmp = sample(ctx_sampling, ctx_llava->ctx_moses, &n_past);
        if (strcmp(tmp, "</s>") == 0) break;
        if (strstr(tmp, "###")) break; // Yi-VL behavior

        printf("%s", tmp);
        fflush(stdout);
    }

    moses_sampling_free(ctx_sampling);
    printf("\n");
}


static struct llava_context * llava_init(gpt_params * params) {
    const char * clip_path = params->mmproj.c_str();

    auto prompt = params->prompt;
    if (prompt.empty()) {
        prompt = "describe the image in detail.";
    }

    auto ctx_clip = clip_model_load(clip_path, /*verbosity=*/ 1);

    moses_backend_init(params->numa);

    moses_model_params model_params = moses_model_params_from_gpt_params(*params);

    moses_model * model = moses_load_model_from_file(params->model.c_str(), model_params);
    if (model == NULL) {
        fprintf(stderr , "%s: error: unable to load model\n" , __func__);
        return NULL;
    }

    moses_context_params ctx_params = moses_context_params_from_gpt_params(*params);
    ctx_params.n_ctx           = params->n_ctx < 2048 ? 2048 : params->n_ctx; // we need a longer context size to process image embeddings

    moses_context * ctx_moses = moses_new_context_with_model(model, ctx_params);

    if (ctx_moses == NULL) {
        fprintf(stderr , "%s: error: failed to create the moses_context\n" , __func__);
        return NULL;
    }

    auto ctx_llava = (struct llava_context *)malloc(sizeof(llava_context));

    ctx_llava->ctx_moses = ctx_moses;
    ctx_llava->ctx_clip = ctx_clip;
    ctx_llava->model = model;
    return ctx_llava;
}

static void llava_free(struct llava_context * ctx_llava) {
    if (ctx_llava->ctx_clip) {
        clip_free(ctx_llava->ctx_clip);
        ctx_llava->ctx_clip = NULL;
    }

    moses_free(ctx_llava->ctx_moses);
    moses_free_model(ctx_llava->model);
    moses_backend_free();
}

int main(int argc, char ** argv) {
    ggml_time_init();

    gpt_params params;

    if (!gpt_params_parse(argc, argv, params)) {
        show_additional_info(argc, argv);
        return 1;
    }
    if (params.mmproj.empty() || (params.image.empty() && !prompt_contains_image(params.prompt))) {
        gpt_print_usage(argc, argv, params);
        show_additional_info(argc, argv);
        return 1;
    }

    auto ctx_llava = llava_init(&params);
    if (ctx_llava == NULL) {
        fprintf(stderr, "%s: error: failed to init llava\n", __func__);
        return 1;
    }

    auto image_embed = load_image(ctx_llava, &params);
    if (!image_embed) {
        return 1;
    }

    // process the prompt
    process_prompt(ctx_llava, image_embed, &params, params.prompt);

    moses_print_timings(ctx_llava->ctx_moses);

    llava_image_embed_free(image_embed);
    llava_free(ctx_llava);
    return 0;
}
