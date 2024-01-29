#pragma once

#include "moses.h"

#include "grammar-parser.h"

#include <string>
#include <vector>
#include <unordered_map>

// sampling parameters
typedef struct moses_sampling_params {
    int32_t     n_prev                = 64;       // number of previous tokens to remember
    int32_t     n_probs               = 0;        // if greater than 0, output the probabilities of top n_probs tokens.
    int32_t     top_k                 = 40;       // <= 0 to use vocab size
    float       top_p                 = 0.95f;    // 1.0 = disabled
    float       min_p                 = 0.05f;    // 0.0 = disabled
    float       tfs_z                 = 1.00f;    // 1.0 = disabled
    float       typical_p             = 1.00f;    // 1.0 = disabled
    float       temp                  = 0.80f;    // <= 0.0 to sample greedily, 0.0 to not output probabilities
    float       dynatemp_range        = 0.00f;    // 0.0 = disabled
    float       dynatemp_exponent     = 1.00f;    // controls how entropy maps to temperature in dynamic temperature sampler
    int32_t     penalty_last_n        = 64;       // last n tokens to penalize (0 = disable penalty, -1 = context size)
    float       penalty_repeat        = 1.10f;    // 1.0 = disabled
    float       penalty_freq          = 0.00f;    // 0.0 = disabled
    float       penalty_present       = 0.00f;    // 0.0 = disabled
    int32_t     mirostat              = 0;        // 0 = disabled, 1 = mirostat, 2 = mirostat 2.0
    float       mirostat_tau          = 5.00f;    // target entropy
    float       mirostat_eta          = 0.10f;    // learning rate
    bool        penalize_nl           = true;     // consider newlines as a repeatable token
    std::string samplers_sequence     = "kfypmt"; // top_k, tail_free, typical_p, top_p, min_p, temp

    std::string grammar;  // optional BNF-like grammar to constrain sampling

    // Classifier-Free Guidance
    // https://arxiv.org/abs/2306.17806
    std::string cfg_negative_prompt; // string to help guidance
    float       cfg_scale     = 1.f; // how strong is guidance

    std::unordered_map<moses_token, float> logit_bias; // logit bias for specific tokens

    std::vector<moses_token> penalty_prompt_tokens;
    bool                     use_penalty_prompt_tokens = false;
} moses_sampling_params;

// general sampler context
// TODO: move to moses.h
struct moses_sampling_context {
    // parameters that will be used for sampling
    moses_sampling_params params;

    // mirostat sampler state
    float mirostat_mu;

    moses_grammar * grammar;

    // internal
    grammar_parser::parse_state parsed_grammar;

    // TODO: replace with ring-buffer
    std::vector<moses_token>      prev;
    std::vector<moses_token_data> cur;
};

#include "common.h"

// Create a new sampling context instance.
struct moses_sampling_context * moses_sampling_init(const struct moses_sampling_params & params);

void moses_sampling_free(struct moses_sampling_context * ctx);

// Reset the sampler context
// - clear prev tokens
// - reset grammar
void moses_sampling_reset(moses_sampling_context * ctx);

// Copy the sampler context
void moses_sampling_cp(moses_sampling_context * src, moses_sampling_context * dst);

// Get the last sampled token
moses_token moses_sampling_last(moses_sampling_context * ctx);

// Get a string representation of the last sampled tokens
std::string moses_sampling_prev_str(moses_sampling_context * ctx_sampling, moses_context * ctx_main, int n);

// Print sampling parameters into a string
std::string moses_sampling_print(const moses_sampling_params & params);

// Print sampling order into a string
std::string moses_sampling_order_print(const moses_sampling_params & params);

// this is a common sampling function used across the examples for convenience
// it can serve as a starting point for implementing your own sampling function
// Note: When using multiple sequences, it is the caller's responsibility to call
//       moses_sampling_reset when a sequence ends
//
// required:
//  - ctx_main:     context to use for sampling
//  - ctx_sampling: sampling-specific context
//
// optional:
//  - ctx_cfg:      context to use for classifier-free guidance
//  - idx:          sample from moses_get_logits_ith(ctx, idx)
//
// returns:
//  - token:      sampled token
//  - candidates: vector of candidate tokens
//
moses_token moses_sampling_sample(
        struct moses_sampling_context * ctx_sampling,
        struct moses_context * ctx_main,
        struct moses_context * ctx_cfg,
        int idx = 0);

void moses_sampling_accept(
        struct moses_sampling_context * ctx_sampling,
        struct moses_context * ctx_main,
        moses_token id,
        bool apply_grammar);
