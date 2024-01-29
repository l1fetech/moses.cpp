#include "common.h"
#include "moses.h"

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

int main(int argc, char ** argv) {
    if (argc < 3 || argv[1][0] == '-') {
        printf("usage: %s MODEL_PATH PROMPT [--ids]\n" , argv[0]);
        return 1;
    }

    const char * model_path = argv[1];
    const char * prompt     = argv[2];

    const bool printing_ids = argc > 3 && std::string(argv[3]) == "--ids";

    moses_backend_init(false);

    moses_model_params model_params = moses_model_default_params();
    model_params.vocab_only = true;
    moses_model * model = moses_load_model_from_file(model_path, model_params);

    moses_context_params ctx_params = moses_context_default_params();
    moses_context * ctx = moses_new_context_with_model(model, ctx_params);

    const bool add_bos = moses_should_add_bos_token(model);

    std::vector<moses_token> tokens;

    tokens = ::moses_tokenize(model, prompt, add_bos, true);

    for (int i = 0; i < (int) tokens.size(); i++) {
        if (printing_ids) {
            printf("%d\n", tokens[i]);
        } else {
            printf("%6d -> '%s'\n", tokens[i], moses_token_to_piece(ctx, tokens[i]).c_str());
        }
    }

    return 0;
}
