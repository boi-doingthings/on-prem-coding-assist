#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"
# shellcheck source=enroot-env.sh
source "${repo_root}/scripts/enroot-env.sh"

container_name="${DYNAMO_ENROOT_NAME:-dynamo-vllm}"
image="${DYNAMO_ENROOT_IMAGE:-${repo_root}/.state/enroot/images/dynamo-vllm-1.3.0.sqsh}"
model_cache="${DYNAMO_MODEL_CACHE:-${repo_root}/.state/model-cache}"
log_dir="${repo_root}/.state/logs"
pid_file="${repo_root}/.state/enroot-disagg.pid"

if [[ "${1:-}" == "--detach" ]]; then
  mkdir -p "${log_dir}"
  if [[ -s "${pid_file}" ]] && kill -0 "$(<"${pid_file}")" 2>/dev/null; then
    printf 'Enroot Dynamo is already running with PID %s.\n' "$(<"${pid_file}")"
    exit 0
  fi
  rm -f "${pid_file}"
  if [[ -s "${log_dir}/enroot-disagg.log" ]]; then
    mv "${log_dir}/enroot-disagg.log" \
      "${log_dir}/enroot-disagg.$(date -u +%Y%m%dT%H%M%SZ).log"
  fi
  setsid nohup "$0" --foreground \
    >"${log_dir}/enroot-disagg.log" 2>&1 </dev/null &
  printf '%s\n' "$!" >"${pid_file}"
  printf 'Started Enroot Dynamo with PID %s; log: %s\n' "$!" \
    "${log_dir}/enroot-disagg.log"
  exit 0
fi

if [[ ! -f "${image}" ]]; then
  printf 'Missing Enroot image: %s\n' "${image}" >&2
  exit 1
fi

if [[ ! -d "${ENROOT_DATA_PATH}/${container_name}" ]]; then
  enroot create --name "${container_name}" "${image}"
fi

docker compose -f "${repo_root}/deploy/local/compose.yaml" up -d nats etcd
mkdir -p "${model_cache}"

exec enroot start \
  --rw \
  --mount "${repo_root}/deploy/local:/lab" \
  --mount "${model_cache}:/model-cache" \
  --env DYNAMO_PREFILL_GPU="${DYNAMO_PREFILL_GPU:-0}" \
  --env DYNAMO_DECODE_GPUS="${DYNAMO_DECODE_GPUS:-1,2}" \
  --env DYNAMO_MODEL="${DYNAMO_MODEL:-nvidia/Qwen3.5-122B-A10B-NVFP4}" \
  --env DYNAMO_SERVED_MODEL="${DYNAMO_SERVED_MODEL:-Qwen/Qwen3.5-122B-A10B}" \
  --env HF_XET_HIGH_PERFORMANCE=1 \
  --env UCX_RCACHE_MAX_UNRELEASED=1024 \
  "${container_name}" bash /lab/start-disagg.sh
