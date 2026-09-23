#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"

runtime_image="${DYNAMO_RUNTIME_IMAGE:-nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.3.0}"
model="${DYNAMO_MODEL:-nvidia/Qwen3.5-122B-A10B-NVFP4}"
model_cache="${DYNAMO_MODEL_CACHE:-${repo_root}/.state/model-cache}"
download_user="${DYNAMO_DOWNLOAD_USER:-0:0}"

mkdir -p "${model_cache}"
env_args=()
if [[ -n "${HF_TOKEN:-}" ]]; then
  env_args+=(--env HF_TOKEN)
fi
if [[ "${DYNAMO_DISABLE_XET:-0}" == "1" ]]; then
  env_args+=(--env HF_HUB_DISABLE_XET=1)
else
  env_args+=(--env HF_XET_HIGH_PERFORMANCE=1)
fi

docker run --rm \
  --user "${download_user}" \
  --network host \
  --env HF_HOME=/model-cache \
  "${env_args[@]}" \
  --volume "${model_cache}:/model-cache" \
  "${runtime_image}" \
  hf download "${model}"
