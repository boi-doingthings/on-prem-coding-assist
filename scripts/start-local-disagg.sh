#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"

runtime_image="${DYNAMO_RUNTIME_IMAGE:-nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.3.0}"
container_name="${DYNAMO_CONTAINER_NAME:-dynamo-qwen35-disagg}"
model_cache="${DYNAMO_MODEL_CACHE:-${repo_root}/.state/model-cache}"

docker compose -f "${repo_root}/deploy/local/compose.yaml" up -d nats etcd
mkdir -p "${model_cache}"

env_args=()
if [[ -n "${HF_TOKEN:-}" ]]; then
  env_args+=(--env HF_TOKEN)
fi

docker run --detach \
  --name "${container_name}" \
  --user 0:0 \
  --gpus all \
  --network host \
  --ipc host \
  --ulimit memlock=-1:-1 \
  --cap-add IPC_LOCK \
  --cap-add SYS_RESOURCE \
  --env DYNAMO_PREFILL_GPU="${DYNAMO_PREFILL_GPU:-0}" \
  --env DYNAMO_DECODE_GPUS="${DYNAMO_DECODE_GPUS:-1,2}" \
  --env DYNAMO_MODEL="${DYNAMO_MODEL:-nvidia/Qwen3.5-122B-A10B-NVFP4}" \
  --env DYNAMO_SERVED_MODEL="${DYNAMO_SERVED_MODEL:-Qwen/Qwen3.5-122B-A10B}" \
  --env HF_XET_HIGH_PERFORMANCE=1 \
  "${env_args[@]}" \
  --volume "${model_cache}:/model-cache" \
  --volume "${repo_root}/deploy/local:/lab:ro" \
  "${runtime_image}" \
  bash /lab/start-disagg.sh

printf 'Started %s with 1P/2D on GPUs %s/%s\n' \
  "${container_name}" "${DYNAMO_PREFILL_GPU:-0}" "${DYNAMO_DECODE_GPUS:-1,2}"
