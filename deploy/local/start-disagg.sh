#!/usr/bin/env bash
set -euo pipefail

trap 'status=$?; trap - EXIT; kill 0 2>/dev/null || true; exit "$status"' EXIT

model="${DYNAMO_MODEL:-nvidia/Qwen3.5-122B-A10B-NVFP4}"
served_model="${DYNAMO_SERVED_MODEL:-Qwen/Qwen3.5-122B-A10B}"
prefill_gpu="${DYNAMO_PREFILL_GPU:-0}"
decode_gpus="${DYNAMO_DECODE_GPUS:-1,2}"
prefill_kv_transfer_config='{"kv_connector":"NixlConnector","kv_role":"kv_producer","kv_connector_extra_config":{"num_threads":8}}'
decode_kv_transfer_config='{"kv_connector":"NixlConnector","kv_role":"kv_consumer","kv_connector_extra_config":{"num_threads":8}}'

export PYTHONHASHSEED=0
export HOME=/tmp/dynamo-home
export XDG_CACHE_HOME=/tmp/dynamo-cache
export HF_HOME=/model-cache
export TRITON_CACHE_DIR=/tmp/.triton-cache
export VLLM_CONFIG_ROOT=/tmp/vllm-config
export VLLM_CACHE_ROOT=/tmp/vllm-cache
export HF_MODULES_CACHE=/tmp/hf_modules
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export VLLM_ALLREDUCE_USE_SYMM_MEM=0
export VLLM_SSM_CONV_STATE_LAYOUT=DS
export VLLM_ALLOW_CHUNKED_LOCAL_ATTN_WITH_HYBRID_KV_CACHE=1
export DYN_VLLM_APPEND_PREFILL_OUTPUT_TOKENS=0
export UCX_RCACHE_MAX_UNRELEASED=1024

mkdir -p "${HOME}" "${XDG_CACHE_HOME}" "${TRITON_CACHE_DIR}" \
  "${VLLM_CONFIG_ROOT}" "${VLLM_CACHE_ROOT}" "${HF_MODULES_CACHE}"

python3 -m dynamo.frontend \
  --router-mode kv \
  --router-kv-events \
  --kv-cache-block-size 64 \
  --http-port 8000 \
  --trust-remote-code &

CUDA_VISIBLE_DEVICES="${prefill_gpu}" \
DYN_SYSTEM_PORT=18081 \
VLLM_NIXL_SIDE_CHANNEL_PORT=21096 \
python3 -m dynamo.vllm \
  --model="${model}" \
  --served-model-name="${served_model}" \
  --trust-remote-code \
  --enable-multimodal \
  --enable-mm-embeds \
  --dyn-tool-call-parser qwen3_coder \
  --dyn-reasoning-parser qwen3 \
  --tensor-parallel-size=1 \
  --quantization=modelopt_fp4 \
  --kv-cache-dtype=fp8 \
  --moe-backend=flashinfer_trtllm \
  --mamba-ssm-cache-dtype=float16 \
  --no-disable-hybrid-kv-cache-manager \
  --enable-prefix-caching \
  --block-size=64 \
  --max-num-seqs=32 \
  --max-num-batched-tokens=16384 \
  --gpu-memory-utilization=0.9 \
  --disaggregation-mode=prefill \
  --kv-transfer-config="${prefill_kv_transfer_config}" \
  --kv-events-config='{"publisher":"zmq","topic":"kv-events","endpoint":"tcp://*:5571","enable_kv_cache_events":true}' &

IFS=',' read -ra gpus <<< "${decode_gpus}"
worker_index=0
for gpu in "${gpus[@]}"; do
  system_port=$((18082 + worker_index))
  side_port=$((21097 + worker_index))

  CUDA_VISIBLE_DEVICES="${gpu}" \
  DYN_SYSTEM_PORT="${system_port}" \
  VLLM_NIXL_SIDE_CHANNEL_PORT="${side_port}" \
  python3 -m dynamo.vllm \
    --model="${model}" \
    --served-model-name="${served_model}" \
    --trust-remote-code \
    --enable-multimodal \
    --enable-mm-embeds \
    --dyn-tool-call-parser qwen3_coder \
    --dyn-reasoning-parser qwen3 \
    --tensor-parallel-size=1 \
    --quantization=modelopt_fp4 \
    --kv-cache-dtype=fp8 \
    --moe-backend=flashinfer_trtllm \
    --mamba-ssm-cache-dtype=float16 \
    --no-disable-hybrid-kv-cache-manager \
    --enable-prefix-caching \
    --block-size=64 \
    --max-num-seqs=128 \
    --max-num-batched-tokens=16384 \
    --gpu-memory-utilization=0.9 \
    --disaggregation-mode=decode \
    --no-async-scheduling \
    --kv-transfer-config="${decode_kv_transfer_config}" &

  worker_index=$((worker_index + 1))
done

wait -n
