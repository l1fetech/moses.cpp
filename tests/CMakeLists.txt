function(moses_build_executable source)
    get_filename_component(TEST_TARGET ${source} NAME_WE)
    add_executable(${TEST_TARGET} ${source} get-model.cpp)
    install(TARGETS ${TEST_TARGET} RUNTIME)
    target_link_libraries(${TEST_TARGET} PRIVATE common)
endfunction()

function(moses_test_executable name source)
    get_filename_component(TEST_TARGET ${source} NAME_WE)
    add_test(NAME ${name} COMMAND $<TARGET_FILE:${TEST_TARGET}> ${ARGN})
    set_property(TEST ${name} PROPERTY LABELS "main")
endfunction()

function(moses_build_and_test_executable source)
    moses_build_and_test_executable_with_label(${source} "main")
endfunction()

function(moses_build_and_test_executable_with_label source label)
    get_filename_component(TEST_TARGET ${source} NAME_WE)
    add_executable(${TEST_TARGET} ${source} get-model.cpp)
    install(TARGETS ${TEST_TARGET} RUNTIME)
    target_link_libraries(${TEST_TARGET} PRIVATE common)
    add_test(NAME ${TEST_TARGET} COMMAND $<TARGET_FILE:${TEST_TARGET}> ${ARGN})
    set_property(TEST ${TEST_TARGET} PROPERTY LABELS ${label})
endfunction()

# moses_build_and_test_executable(test-double-float.cpp) # SLOW
moses_build_and_test_executable(test-quantize-fns.cpp)
moses_build_and_test_executable(test-quantize-perf.cpp)
moses_build_and_test_executable(test-sampling.cpp)

moses_build_executable(test-tokenizer-0-moses.cpp)
moses_test_executable (test-tokenizer-0-moses test-tokenizer-0-moses.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-moses.gguf)

moses_build_executable(test-tokenizer-0-falcon.cpp)
moses_test_executable (test-tokenizer-0-falcon test-tokenizer-0-falcon.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-falcon.gguf)

moses_build_executable(test-tokenizer-1-moses.cpp)
moses_test_executable (test-tokenizer-1-moses    test-tokenizer-1-moses.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-moses.gguf)
moses_test_executable (test-tokenizer-1-baichuan test-tokenizer-1-moses.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-baichuan.gguf)

moses_build_executable(test-tokenizer-1-bpe.cpp)
moses_test_executable (test-tokenizer-1-falcon           test-tokenizer-1-bpe.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-falcon.gguf)
moses_test_executable (test-tokenizer-1-aquila           test-tokenizer-1-bpe.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-aquila.gguf)
moses_test_executable (test-tokenizer-1-mpt              test-tokenizer-1-bpe.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-mpt.gguf)
moses_test_executable (test-tokenizer-1-stablelm-3b-4e1t test-tokenizer-1-bpe.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-stablelm-3b-4e1t.gguf)
moses_test_executable (test-tokenizer-1-gpt-neox         test-tokenizer-1-bpe.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-gpt-neox.gguf)
moses_test_executable (test-tokenizer-1-refact           test-tokenizer-1-bpe.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-refact.gguf)
moses_test_executable (test-tokenizer-1-starcoder        test-tokenizer-1-bpe.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-starcoder.gguf)
moses_test_executable (test-tokenizer-1-gpt2             test-tokenizer-1-bpe.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-gpt2.gguf)
# moses_test_executable (test-tokenizer-1-bloom test-tokenizer-1-bpe.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../models/ggml-vocab-bloom.gguf) # BIG

moses_build_and_test_executable(test-grammar-parser.cpp)
moses_build_and_test_executable(test-moses-grammar.cpp)
moses_build_and_test_executable(test-grad0.cpp)
# moses_build_and_test_executable(test-opt.cpp) # SLOW
moses_build_and_test_executable(test-backend-ops.cpp)

moses_build_and_test_executable(test-rope.cpp)

moses_build_and_test_executable_with_label(test-model-load-cancel.cpp "model")
moses_build_and_test_executable_with_label(test-autorelease.cpp "model")

# dummy executable - not installed
get_filename_component(TEST_TARGET test-c.c NAME_WE)
add_executable(${TEST_TARGET} test-c.c)
target_link_libraries(${TEST_TARGET} PRIVATE moses)
