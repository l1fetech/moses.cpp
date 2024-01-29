#include "common.h"
#include "moses.h"

#include <vector>
#include <cstdio>
#include <chrono>

int main(int argc, char ** argv) {
    gpt_params params;

    params.prompt = "The quick brown fox";

    if (!gpt_params_parse(argc, argv, params)) {
        return 1;
    }

    print_build_info();

    if (params.n_predict < 0) {
        params.n_predict = 16;
    }

    auto n_past = 0;

    std::string result0;
    std::string result1;

    // init
    moses_model * model;
    moses_context * ctx;

    std::tie(model, ctx) = moses_init_from_gpt_params(params);
    if (model == nullptr || ctx == nullptr) {
        fprintf(stderr, "%s : failed to init\n", __func__);
        return 1;
    }

    // tokenize prompt
    auto tokens = moses_tokenize(ctx, params.prompt, true);

    // evaluate prompt
    moses_decode(ctx, moses_batch_get_one(tokens.data(), tokens.size(), n_past, 0));
    n_past += tokens.size();

    // save state (rng, logits, embedding and kv_cache) to file
    {
        std::vector<uint8_t> state_mem(moses_get_state_size(ctx));
        const size_t written = moses_copy_state_data(ctx, state_mem.data());

        FILE *fp_write = fopen("dump_state.bin", "wb");
        fwrite(state_mem.data(), 1, written, fp_write);
        fclose(fp_write);

        fprintf(stderr, "%s : serialized state into %zd out of a maximum of %zd bytes\n", __func__, written, state_mem.size());
    }

    // save state (last tokens)
    const auto n_past_saved = n_past;

    // first run
    printf("\nfirst run: %s", params.prompt.c_str());

    for (auto i = 0; i < params.n_predict; i++) {
        auto * logits = moses_get_logits(ctx);
        auto n_vocab = moses_n_vocab(model);

        std::vector<moses_token_data> candidates;
        candidates.reserve(n_vocab);
        for (moses_token token_id = 0; token_id < n_vocab; token_id++) {
            candidates.emplace_back(moses_token_data{token_id, logits[token_id], 0.0f});
        }
        moses_token_data_array candidates_p = { candidates.data(), candidates.size(), false };
        auto next_token = moses_sample_token(ctx, &candidates_p);
        auto next_token_str = moses_token_to_piece(ctx, next_token);

        printf("%s", next_token_str.c_str());
        result0 += next_token_str;

        if (moses_decode(ctx, moses_batch_get_one(&next_token, 1, n_past, 0))) {
            fprintf(stderr, "\n%s : failed to evaluate\n", __func__);
            moses_free(ctx);
            moses_free_model(model);
            return 1;
        }
        n_past += 1;
    }

    printf("\n\n");

    // free old context
    moses_free(ctx);

    // make new context
    auto * ctx2 = moses_new_context_with_model(model, moses_context_params_from_gpt_params(params));

    printf("\nsecond run: %s", params.prompt.c_str());

    // load state (rng, logits, embedding and kv_cache) from file
    {
        std::vector<uint8_t> state_mem(moses_get_state_size(ctx2));

        FILE * fp_read = fopen("dump_state.bin", "rb");
        const size_t read = fread(state_mem.data(), 1, state_mem.size(), fp_read);
        fclose(fp_read);

        if (read != moses_set_state_data(ctx2, state_mem.data())) {
            fprintf(stderr, "\n%s : failed to read state\n", __func__);
            moses_free(ctx2);
            moses_free_model(model);
            return 1;
        }

        fprintf(stderr, "%s : deserialized state from %zd out of a maximum of %zd bytes\n", __func__, read, state_mem.size());
    }

    // restore state (last tokens)
    n_past = n_past_saved;

    // second run
    for (auto i = 0; i < params.n_predict; i++) {
        auto * logits = moses_get_logits(ctx2);
        auto n_vocab = moses_n_vocab(model);
        std::vector<moses_token_data> candidates;
        candidates.reserve(n_vocab);
        for (moses_token token_id = 0; token_id < n_vocab; token_id++) {
            candidates.emplace_back(moses_token_data{token_id, logits[token_id], 0.0f});
        }
        moses_token_data_array candidates_p = { candidates.data(), candidates.size(), false };
        auto next_token = moses_sample_token(ctx2, &candidates_p);
        auto next_token_str = moses_token_to_piece(ctx2, next_token);

        printf("%s", next_token_str.c_str());
        result1 += next_token_str;

        if (moses_decode(ctx2, moses_batch_get_one(&next_token, 1, n_past, 0))) {
            fprintf(stderr, "\n%s : failed to evaluate\n", __func__);
            moses_free(ctx2);
            moses_free_model(model);
            return 1;
        }
        n_past += 1;
    }

    printf("\n");

    moses_free(ctx2);
    moses_free_model(model);

    if (result0 != result1) {
        fprintf(stderr, "\n%s : error : the 2 generations are different\n", __func__);
        return 1;
    }

    fprintf(stderr, "\n%s : success\n", __func__);

    return 0;
}
