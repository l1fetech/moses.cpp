#pragma once

#include <string>
#include <vector>
#include <set>
#include <mutex>
#include <condition_variable>
#include <unordered_map>

#include "json.hpp"
#include "utils.hpp"

#define DEFAULT_OAICOMPAT_MODEL "gpt-3.5-turbo-0613"

using json = nlohmann::json;

inline static json oaicompat_completion_params_parse(
    const json &body /* openai api json semantics */)
{
    json moses_params;

    moses_params["__oaicompat"] = true;

    // Map OpenAI parameters to moses.cpp parameters
    //
    // For parameters that are defined by the OpenAI documentation (e.g.
    // temperature), we explicitly specify OpenAI's intended default; we
    // need to do that because sometimes OpenAI disagrees with moses.cpp
    //
    // https://platform.openai.com/docs/api-reference/chat/create
    moses_sampling_params default_sparams;
    moses_params["model"]             = json_value(body, "model", std::string("unknown"));
    moses_params["prompt"]            = format_chatml(body["messages"]); // OpenAI 'messages' to moses.cpp 'prompt'
    moses_params["cache_prompt"]      = json_value(body, "cache_prompt", false);
    moses_params["temperature"]       = json_value(body, "temperature", 0.0);
    moses_params["top_k"]             = json_value(body, "top_k", default_sparams.top_k);
    moses_params["top_p"]             = json_value(body, "top_p", 1.0);
    moses_params["n_predict"]         = json_value(body, "max_tokens", -1);
    moses_params["logit_bias"]        = json_value(body, "logit_bias",json::object());
    moses_params["frequency_penalty"] = json_value(body, "frequency_penalty", 0.0);
    moses_params["presence_penalty"]  = json_value(body, "presence_penalty", 0.0);
    moses_params["seed"]              = json_value(body, "seed", MOSES_DEFAULT_SEED);
    moses_params["stream"]            = json_value(body, "stream", false);
    moses_params["mirostat"]          = json_value(body, "mirostat", default_sparams.mirostat);
    moses_params["mirostat_tau"]      = json_value(body, "mirostat_tau", default_sparams.mirostat_tau);
    moses_params["mirostat_eta"]      = json_value(body, "mirostat_eta", default_sparams.mirostat_eta);
    moses_params["penalize_nl"]       = json_value(body, "penalize_nl", default_sparams.penalize_nl);
    moses_params["typical_p"]         = json_value(body, "typical_p", default_sparams.typical_p);
    moses_params["repeat_last_n"]     = json_value(body, "repeat_last_n", default_sparams.penalty_last_n);
    moses_params["ignore_eos"]        = json_value(body, "ignore_eos", false);
    moses_params["tfs_z"]             = json_value(body, "tfs_z", default_sparams.tfs_z);

    if (body.count("grammar") != 0) {
        moses_params["grammar"] = json_value(body, "grammar", json::object());
    }

    // Handle 'stop' field
    if (body.contains("stop") && body["stop"].is_string()) {
        moses_params["stop"] = json::array({body["stop"].get<std::string>()});
    } else {
        moses_params["stop"] = json_value(body, "stop", json::array());
    }

    // Ensure there is ChatML-specific end sequence among stop words
    moses_params["stop"].push_back("<|im_end|>");

    return moses_params;
}

inline static json format_final_response_oaicompat(const json &request, const task_result &response, bool streaming = false)
{
    json result = response.result_json;

    bool stopped_word        = result.count("stopped_word") != 0;
    bool stopped_eos         = json_value(result, "stopped_eos", false);
    int num_tokens_predicted = json_value(result, "tokens_predicted", 0);
    int num_prompt_tokens    = json_value(result, "tokens_evaluated", 0);
    std::string content      = json_value(result, "content", std::string(""));

    std::string finish_reason = "length";
    if (stopped_word || stopped_eos) {
        finish_reason = "stop";
    }

    json choices =
        streaming ? json::array({json{{"finish_reason", finish_reason},
                                        {"index", 0},
                                        {"delta", json::object()}}})
                  : json::array({json{{"finish_reason", finish_reason},
                                        {"index", 0},
                                        {"message", json{{"content", content},
                                                         {"role", "assistant"}}}}});

    std::time_t t = std::time(0);

    json res =
        json{{"choices", choices},
            {"created", t},
            {"model",
                json_value(request, "model", std::string(DEFAULT_OAICOMPAT_MODEL))},
            {"object", streaming ? "chat.completion.chunk" : "chat.completion"},
            {"usage",
                json{{"completion_tokens", num_tokens_predicted},
                     {"prompt_tokens",     num_prompt_tokens},
                     {"total_tokens",      num_tokens_predicted + num_prompt_tokens}}},
            {"id", gen_chatcmplid()}};

    if (server_verbose) {
        res["__verbose"] = result;
    }

    if (result.contains("completion_probabilities")) {
        res["completion_probabilities"] = json_value(result, "completion_probabilities", json::array());
    }

    return res;
}

// return value is vector as there is one case where we might need to generate two responses
inline static std::vector<json> format_partial_response_oaicompat(const task_result &response) {
    json result = response.result_json;

    if (!result.contains("model") || !result.contains("oaicompat_token_ctr")) {
        return std::vector<json>({response.result_json});
    }

    bool first = json_value(result, "oaicompat_token_ctr", 0) == 0;
    std::string modelname = json_value(result, "model", std::string(DEFAULT_OAICOMPAT_MODEL));

    bool stopped_word   = json_value(result, "stopped_word", false);
    bool stopped_eos    = json_value(result, "stopped_eos", false);
    bool stopped_limit  = json_value(result, "stopped_limit", false);
    std::string content = json_value(result, "content", std::string(""));

    std::string finish_reason;
    if (stopped_word || stopped_eos) {
        finish_reason = "stop";
    }
    if (stopped_limit) {
        finish_reason = "length";
    }

    std::time_t t = std::time(0);

    json choices;

    if (!finish_reason.empty()) {
        choices = json::array({json{{"finish_reason", finish_reason},
                                    {"index", 0},
                                    {"delta", json::object()}}});
    } else {
        if (first) {
            if (content.empty()) {
                choices = json::array({json{{"finish_reason", nullptr},
                                            {"index", 0},
                                            {"delta", json{{"role", "assistant"}}}}});
            } else {
                // We have to send this as two updates to conform to openai behavior
                json initial_ret = json{{"choices", json::array({json{
                                        {"finish_reason", nullptr},
                                        {"index", 0},
                                        {"delta", json{
                                            {"role", "assistant"}
                                        }}}})},
                            {"created", t},
                            {"id", gen_chatcmplid()},
                            {"model", modelname},
                            {"object", "chat.completion.chunk"}};

                json second_ret = json{
                            {"choices", json::array({json{{"finish_reason", nullptr},
                                                            {"index", 0},
                                                            {"delta", json{
                                                            {"content", content}}}
                                                            }})},
                            {"created", t},
                            {"id", gen_chatcmplid()},
                            {"model", modelname},
                            {"object", "chat.completion.chunk"}};

                return std::vector<json>({initial_ret, second_ret});
            }
        } else {
            // Some idiosyncrasy in task processing logic makes several trailing calls
            // with empty content, we ignore these at the calee site.
            if (content.empty()) {
                return std::vector<json>({json::object()});
            }

            choices = json::array({json{
                {"finish_reason", nullptr},
                {"index", 0},
                {"delta",
                json{
                    {"content", content},
                }},
            }});
        }
    }

    json ret = json{{"choices", choices},
                    {"created", t},
                    {"id", gen_chatcmplid()},
                    {"model", modelname},
                    {"object", "chat.completion.chunk"}};

    return std::vector<json>({ret});
}
