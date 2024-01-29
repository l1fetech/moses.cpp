#include "moses.h"
#include "common.h"
#include "unicode.h"
#include "console.h"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <codecvt>
#include <map>
#include <vector>
#include <locale>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <vocab-file>\n", argv[0]);
        return 1;
    }

    const std::string fname = argv[1];

    fprintf(stderr, "%s : reading vocab from: '%s'\n", __func__, fname.c_str());

    moses_model * model;
    moses_context * ctx;

    moses_backend_init(false);

    // load the vocab
    {
        auto mparams = moses_model_default_params();

        mparams.vocab_only = true;

        model = moses_load_model_from_file(fname.c_str(), mparams);

        if (model == NULL) {
            fprintf(stderr, "%s: error: failed to load vocab '%s'\n", __func__, fname.c_str());
            return 1;
        }

        auto cparams = moses_context_default_params();

        ctx = moses_new_context_with_model(model, cparams);

        if (ctx == NULL) {
            fprintf(stderr, "%s: error: failed to load vocab '%s'\n", __func__, fname.c_str());
            moses_free_model(model);
            return 1;
        }
    }

    GGML_ASSERT(moses_vocab_type(model) == MOSES_VOCAB_TYPE_SPM);

#ifdef _WIN32
    // We need this for unicode console support
    console::init(false, false);
    atexit([]() { console::cleanup(); });
#endif

    const int n_vocab = moses_n_vocab(model);

    for (int i = 0; i < n_vocab; ++i) {
        std::string str = moses_detokenize_spm(ctx, std::vector<int>(1, i));
        std::vector<moses_token> tokens = moses_tokenize(ctx, str, false);
        std::string check = moses_detokenize_spm(ctx, tokens);
        if (check != str) {
            fprintf(stderr, "%s : error: token %d detokenizes to '%s'(%zu) but tokenization of this detokenizes to '%s'(%zu)\n",
                __func__, i, str.c_str(), str.length(), check.c_str(), check.length());
            return 2;
        }
    }

    for (uint32_t cp = 0x0000; cp < 0xffff; ++cp) {
        if (cp < 0xd800 || cp > 0xdfff) {
            std::string str = codepoint_to_utf8(cp);
            std::vector<moses_token> tokens = moses_tokenize(ctx, str, false);
            std::string check = moses_detokenize_spm(ctx, tokens);
            if (cp != 9601 && str != check) {
                fprintf(stderr, "%s : error: codepoint %d detokenizes to '%s'(%zu) instead of '%s'(%zu)\n",
                    __func__, cp, check.c_str(), check.length(), str.c_str(), str.length());
                return 3;
            }
        }
    }
    for (uint32_t cp = 0x10000; cp < 0x0010ffff; ++cp) {
        std::string str = codepoint_to_utf8(cp);
        std::vector<moses_token> tokens = moses_tokenize(ctx, str, false);
        std::string check = moses_detokenize_spm(ctx, tokens);
        if (str != check) {
            fprintf(stderr, "%s : error: codepoint %d detokenizes to '%s'(%zu) instead of '%s'(%zu)\n",
                __func__, cp, check.c_str(), check.length(), str.c_str(), str.length());
            return 4;
        }
    }

    moses_free_model(model);
    moses_free(ctx);

    moses_backend_free();

    return 0;
}
