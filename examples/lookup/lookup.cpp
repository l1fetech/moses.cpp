#include "common.h"
#include "moses.h"

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

int main(int argc, char ** argv){
    gpt_params params;

    if (!gpt_params_parse(argc, argv, params)) {
        return 1;
    }

    // max/min n-grams size to search for in prompt
    const int ngram_max = 4;
    const int ngram_min = 1;

    // length of the candidate / draft sequence, if match is found
    const int n_draft = params.n_draft;

    const bool dump_kv_cache = params.dump_kv_cache;

#ifndef LOG_DISABLE_LOGS
    log_set_target(log_filename_generator("lookup", "log"));
    LOG_TEE("Log start\n");
    log_dump_cmdline(argc, argv);
#endif // LOG_DISABLE_LOGS

    // init moses.cpp
    moses_backend_init(params.numa);

    moses_model * model = NULL;
    moses_context * ctx = NULL;

    // load the model
    std::tie(model, ctx) = moses_init_from_gpt_params(params);

    // tokenize the prompt
    const bool add_bos = moses_should_add_bos_token(model);
    LOG("add_bos tgt: %d\n", add_bos);

    std::vector<moses_token> inp;
    inp = ::moses_tokenize(ctx, params.prompt, add_bos, true);

    const int max_context_size     = moses_n_ctx(ctx);
    const int max_tokens_list_size = max_context_size - 4;

    if ((int) inp.size() > max_tokens_list_size) {
        fprintf(stderr, "%s: error: prompt too long (%d tokens, max %d)\n", __func__, (int) inp.size(), max_tokens_list_size);
        return 1;
    }

    fprintf(stderr, "\n\n");

    for (auto id : inp) {
        fprintf(stderr, "%s", moses_token_to_piece(ctx, id).c_str());
    }

    fflush(stderr);

    const int n_input = inp.size();

    const auto t_enc_start = ggml_time_us();

    moses_decode(ctx, moses_batch_get_one( inp.data(), n_input - 1, 0,           0));
    moses_decode(ctx, moses_batch_get_one(&inp.back(),           1, n_input - 1, 0));

    const auto t_enc_end = ggml_time_us();

    int n_predict = 0;
    int n_drafted = 0;
    int n_accept  = 0;

    int n_past = inp.size();

    bool has_eos = false;

    struct moses_sampling_context * ctx_sampling = moses_sampling_init(params.sparams);

    std::vector<moses_token> draft;

    moses_batch batch_tgt = moses_batch_init(params.n_ctx, 0, 1);

    // debug
    struct moses_kv_cache_view kvc_view = moses_kv_cache_view_init(ctx, 1);

    const auto t_dec_start = ggml_time_us();

    while (true) {
        // debug
        if (dump_kv_cache) {
            moses_kv_cache_view_update(ctx, &kvc_view);
            dump_kv_cache_view_seqs(kvc_view, 40);
        }

        // print current draft sequence
        LOG("drafted %s\n", LOG_TOKENS_TOSTR_PRETTY(ctx, draft).c_str());

        int i_dft = 0;
        while (true) {
            // sample from the target model
            moses_token id = moses_sampling_sample(ctx_sampling, ctx, NULL, i_dft);

            moses_sampling_accept(ctx_sampling, ctx, id, true);

            const std::string token_str = moses_token_to_piece(ctx, id);

            if (!params.use_color) {
                printf("%s", token_str.c_str());
            }

            if (id == moses_token_eos(model)) {
                has_eos = true;
            }

            ++n_predict;

            // check if the target token matches the draft
            if (i_dft < (int) draft.size() && id == draft[i_dft]) {
                LOG("the sampled target token matches the %dth drafted token (%d, '%s') - accepted\n", i_dft, id, token_str.c_str());
                ++n_accept;
                ++n_past;
                ++i_dft;
                inp.push_back(id);

                if (params.use_color) {
                    // color accepted draft token
                    printf("\033[34m%s\033[0m", token_str.c_str());
                    fflush(stdout);
                }
                continue;
            }

            if (params.use_color) {
                printf("%s", token_str.c_str());
            }
            fflush(stdout);


            LOG("the sampled target token (%d, '%s') did not match, or we ran out of drafted tokens\n", id, token_str.c_str());

            draft.clear();
            draft.push_back(id);
            inp.push_back(id);
            break;
        }

        if ((params.n_predict > 0 && n_predict > params.n_predict) || has_eos) {
            break;
        }

        // KV cache management
        // clean the cache of draft tokens that weren't accepted
        moses_kv_cache_seq_rm(ctx, 0, n_past, -1);

        moses_batch_clear(batch_tgt);
        moses_batch_add(batch_tgt, draft[0], n_past, { 0 }, true);

        // generate n_pred tokens through prompt lookup
        auto prompt_lookup = [&]() -> void {
            int inp_size = inp.size();
            for (int ngram_size = ngram_max ; ngram_size > ngram_min; --ngram_size){
                const moses_token * ngram = &inp[inp_size - ngram_size];

                for (int i = 0; i <= (int) inp_size - (ngram_size * 2); ++i) {
                    bool match = true;
                    for (int j = 0; j < ngram_size; ++j) {
                        if (inp[i + j] != ngram[j]) {
                            match = false;
                            break;
                        }
                    }

                    if (match) {
                        const int startIdx = i + ngram_size;
                        const int endIdx = startIdx + n_draft;
                        if (endIdx < inp_size) {
                            for (int j = startIdx; j < endIdx; ++j) {
                                LOG(" - draft candidate %d: %d\n", j, inp[j]);
                                draft.push_back(inp[j]);
                                moses_batch_add(batch_tgt, inp[j], n_past + (j - startIdx) + 1, { 0 }, true);
                                ++n_drafted;
                            }
                            return;
                        }
                    }
                }
            }
            return;
        };

        prompt_lookup();

        moses_decode(ctx, batch_tgt);
        ++n_past;

        draft.erase(draft.begin());
    }

    auto t_dec_end = ggml_time_us();

    LOG_TEE("\n\n");

    LOG_TEE("encoded %4d tokens in %8.3f seconds, speed: %8.3f t/s\n", n_input,   (t_enc_end - t_enc_start) / 1e6f, inp.size() / ((t_enc_end - t_enc_start) / 1e6f));
    LOG_TEE("decoded %4d tokens in %8.3f seconds, speed: %8.3f t/s\n", n_predict, (t_dec_end - t_dec_start) / 1e6f, n_predict  / ((t_dec_end - t_dec_start) / 1e6f));

    LOG_TEE("\n");
    LOG_TEE("n_draft   = %d\n", n_draft);
    LOG_TEE("n_predict = %d\n", n_predict);
    LOG_TEE("n_drafted = %d\n", n_drafted);
    LOG_TEE("n_accept  = %d\n", n_accept);
    LOG_TEE("accept    = %.3f%%\n", 100.0f * n_accept / n_drafted);

    LOG_TEE("\ntarget:\n");
    moses_print_timings(ctx);

    moses_sampling_free(ctx_sampling);
    moses_batch_free(batch_tgt);

    moses_free(ctx);
    moses_free_model(model);

    moses_backend_free();

    fprintf(stderr, "\n\n");

    return 0;
}