#!/usr/bin/env bash
set -euo pipefail

trap 'status=$?; trap - EXIT; kill 0 2>/dev/null || true; exit "$status"' EXIT

model="${DYNAMO_MODEL:-nvidia/Qwen3.5-122B-A10B-NVFP4}"
served_model="${DYNAMO_SERVED_MODEL:-Qwen/Qwen3.5-122B-A10B}"
gpu_list="${DYNAMO_AGG_GPUS:-0}"
enable_multimodal="${DYNAMO_ENABLE_MULTIMODAL:-1}"
qwen35_nvfp4="${DYNAMO_QWEN35_NVFP4:-1}"

export PYTHONHASHSEED=0
export HF_HOME=/model-cache
export TRITON_CACHE_DIR=/tmp/.triton-cache
export VLLM_CONFIG_ROOT=/tmp/vllm-config
export VLLM_CACHE_ROOT=/tmp/vllm-cache
export HF_MODULES_CACHE=/tmp/hf_modules
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export VLLM_ALLREDUCE_USE_SYMM_MEM=0
export VLLM_SSM_CONV_STATE_LAYOUT=DS
export VLLM_ALLOW_CHUNKED_LOCAL_ATTN_WITH_HYBRID_KV_CACHE=1

python3 -m dynamo.frontend \
  --router-mode kv \
  --router-kv-events \
  --kv-cache-block-size 64 \
  --http-port 8000 \
  --trust-remote-code &

multimodal_args=()
if [[ "${enable_multimodal}" == "1" ]]; then
  multimodal_args+=(--enable-multimodal)
fi

model_args=(
  --dyn-reasoning-parser qwen3
  --tensor-parallel-size=1
  --enable-prefix-caching
  --block-size=64
  --max-num-seqs=32
  --max-num-batched-tokens=16384
  --gpu-memory-utilization=0.9
)
if [[ "${qwen35_nvfp4}" == "1" ]]; then
  model_args+=(
    --dyn-tool-call-parser qwen3_coder
    --quantization=modelopt_fp4
    --kv-cache-dtype=fp8
    --moe-backend=flashinfer_trtllm
    --mamba-ssm-cache-dtype=float16
    --no-disable-hybrid-kv-cache-manager
  )
else
  model_args+=(--dyn-tool-call-parser hermes)
fi

IFS=',' read -ra gpus <<< "${gpu_list}"
worker_index=0
for gpu in "${gpus[@]}"; do
  system_port=$((18081 + worker_index))
  event_port=$((5557 + worker_index))
  side_port=$((21096 + worker_index))

  DYN_SYSTEM_PORT="${system_port}" \
  VLLM_NIXL_SIDE_CHANNEL_PORT="${side_port}" \
  CUDA_VISIBLE_DEVICES="${gpu}" \
  python3 -m dynamo.vllm \
    --model="${model}" \
    --served-model-name="${served_model}" \
    --trust-remote-code \
    "${multimodal_args[@]}" \
    "${model_args[@]}" \
    --kv-events-config="{\"publisher\":\"zmq\",\"topic\":\"kv-events\",\"endpoint\":\"tcp://*:${event_port}\",\"enable_kv_cache_events\":true}" &

  worker_index=$((worker_index + 1))
done

wait -n
