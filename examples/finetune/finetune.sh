#!/bin/bash
cd `dirname $0`
cd ../..

EXE="./finetune"

if [[ ! $MOSES_MODEL_DIR ]]; then MOSES_MODEL_DIR="./models"; fi
if [[ ! $MOSES_TRAINING_DIR ]]; then MOSES_TRAINING_DIR="."; fi

# MODEL="$MOSES_MODEL_DIR/openmoses-3b-v2-q8_0.gguf" # This is the model the readme uses.
MODEL="$MOSES_MODEL_DIR/openmoses-3b-v2.gguf" # An f16 model. Note in this case with "-g", you get an f32-format .BIN file that isn't yet supported if you use it with "main --lora" with GPU inferencing.

while getopts "dg" opt; do
  case $opt in
    d)
      DEBUGGER="gdb --args"
      ;;
    g)
      EXE="./build/bin/Release/finetune"
      GPUARG="--gpu-layers 25"
      ;;
  esac
done

$DEBUGGER $EXE \
        --model-base $MODEL \
        $GPUARG \
        --checkpoint-in  chk-ol3b-shakespeare-LATEST.gguf \
        --checkpoint-out chk-ol3b-shakespeare-ITERATION.gguf \
        --lora-out lora-ol3b-shakespeare-ITERATION.bin \
        --train-data "$MOSES_TRAINING_DIR\shakespeare.txt" \
        --save-every 10 \
        --threads 10 --adam-iter 30 --batch 4 --ctx 64 \
        --use-checkpointing
