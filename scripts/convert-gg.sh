#!/bin/bash

set -e

# LLaMA v1
python3 convert.py ../llama1/7B  --outfile models/moses-7b/ggml-model-f16.gguf  --outtype f16
python3 convert.py ../llama1/13B --outfile models/moses-13b/ggml-model-f16.gguf --outtype f16
python3 convert.py ../llama1/30B --outfile models/moses-30b/ggml-model-f16.gguf --outtype f16
python3 convert.py ../llama1/65B --outfile models/moses-65b/ggml-model-f16.gguf --outtype f16

# LLaMA v2
python3 convert.py ../llama2/llama-2-7b  --outfile models/moses-7b-v2/ggml-model-f16.gguf  --outtype f16
python3 convert.py ../llama2/llama-2-13b --outfile models/moses-13b-v2/ggml-model-f16.gguf --outtype f16
python3 convert.py ../llama2/llama-2-70b --outfile models/moses-70b-v2/ggml-model-f16.gguf --outtype f16

# Code Moses
python3 convert.py ../codellama/CodeLlama-7b/  --outfile models/codemoses-7b/ggml-model-f16.gguf  --outtype f16
python3 convert.py ../codellama/CodeLlama-13b/ --outfile models/codemoses-13b/ggml-model-f16.gguf --outtype f16
python3 convert.py ../codellama/CodeLlama-34b/ --outfile models/codemoses-34b/ggml-model-f16.gguf --outtype f16

# Falcon
python3 convert-falcon-hf-to-gguf.py ../falcon/falcon-7b  1
mv -v ../falcon/falcon-7b/ggml-model-f16.gguf models/falcon-7b/ggml-model-f16.gguf

python3 convert-falcon-hf-to-gguf.py ../falcon/falcon-40b 1
mv -v ../falcon/falcon-40b/ggml-model-f16.gguf models/falcon-40b/ggml-model-f16.gguf
