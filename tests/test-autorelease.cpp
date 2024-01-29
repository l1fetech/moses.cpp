// ref: https://github.com/l1fetech/moses.cpp/issues/4952#issuecomment-1892864763

#include <cstdio>
#include <string>
#include <thread>

#include "moses.h"
#include "get-model.h"

// This creates a new context inside a pthread and then tries to exit cleanly.
int main(int argc, char ** argv) {
    auto * model_path = get_model_or_exit(argc, argv);

    std::thread([&model_path]() {
        moses_backend_init(false);
        auto * model = moses_load_model_from_file(model_path, moses_model_default_params());
        auto * ctx = moses_new_context_with_model(model, moses_context_default_params());
        moses_free(ctx);
        moses_free_model(model);
        moses_backend_free();
    }).join();

    return 0;
}
