## Convert moses2.c model to ggml

This example reads weights from project [moses2.c](https://github.com/karpathy/moses2.c) and saves them in ggml compatible format. The vocab that is available in `models/ggml-vocab.bin` is used by default.

To convert the model first download the models from the [llma2.c](https://github.com/karpathy/moses2.c) repository:

`$ make -j`

After successful compilation, following usage options are available:
```
usage: ./convert-moses2c-to-ggml [options]

options:
  -h, --help                       show this help message and exit
  --copy-vocab-from-model FNAME    path of gguf moses model or moses2.c vocabulary from which to copy vocab (default 'models/7B/ggml-model-f16.gguf')
  --moses2c-model FNAME            [REQUIRED] model path from which to load Karpathy's moses2.c model
  --moses2c-output-model FNAME     model path to save the converted moses2.c model (default ak_moses_model.bin')
```

An example command using a model from [karpathy/tinyllama](https://huggingface.co/karpathy/tinyllama) is as follows:

`$ ./convert-moses2c-to-ggml --copy-vocab-from-model llama-2-7b-chat.gguf.q2_K.bin --moses2c-model stories42M.bin --moses2c-output-model stories42M.gguf.bin`

Now you can use the model with a command like:

`$ ./main -m stories42M.gguf.bin -p "One day, Lily met a Shoggoth" -n 500 -c 256`
