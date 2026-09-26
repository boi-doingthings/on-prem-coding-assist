#!/usr/bin/env bash
# Launch a showcase topology of the portable launcher in the Enroot image on
# this node, with etcd discovery (KV events guaranteed) and a detached log.
#   ./scripts/start-showcase.sh agg8          # 8 x TP1, kv@8000 + round-robin@8001
#   ./scripts/start-showcase.sh disagg-2p6d   # 2 prefill + 6 decode (NIXL)
#   ./scripts/start-showcase.sh disagg-4p4d
# Profile: SHOWCASE_PROFILE (default qwen3.5-122b-a10b-nvfp4).
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/scripts/env.sh"
source "${repo_root}/scripts/enroot-env.sh"

topology="${1:?usage: $0 agg8|agg4|agg2|agg1|disagg-2p6d|disagg-4p4d|disagg-1p7d|cdisagg-2p6d}"
profile="${SHOWCASE_PROFILE:-qwen3.5-122b-a10b-nvfp4}"
container="${SHOWCASE_CONTAINER:-dynamo-vllm-15}"
log="${repo_root}/.state/logs/showcase-${topology}.log"
mkdir -p "$(dirname "${log}")"

set -a
# shellcheck disable=SC1090
source "${repo_root}/config/edu-models/${profile}.env"
set +a
export DYNAMO_DISCOVERY=etcd ETCD_ENDPOINTS=http://127.0.0.1:2379 NATS_SERVER=nats://127.0.0.1:4222
unset DYNAMO_GPUS DYNAMO_PREFILL_GPUS DYNAMO_DECODE_GPUS DYNAMO_EXTRA_FRONTENDS
case "${topology}" in
  agg8) export DYNAMO_GPUS=0,1,2,3,4,5,6,7 DYNAMO_EXTRA_FRONTENDS="round-robin@8001" ;;
  agg4) export DYNAMO_GPUS=0,1,2,3 DYNAMO_EXTRA_FRONTENDS="round-robin@8001" ;;
  agg2) export DYNAMO_GPUS=0,1 ;;
  agg1) export DYNAMO_GPUS=0 ;;
  disagg-1p7d) export DYNAMO_PREFILL_GPUS=0 DYNAMO_DECODE_GPUS=1,2,3,4,5,6,7 ;;
  disagg-2p6d) export DYNAMO_PREFILL_GPUS=0,1 DYNAMO_DECODE_GPUS=2,3,4,5,6,7 ;;
  disagg-4p4d) export DYNAMO_PREFILL_GPUS=0,1,2,3 DYNAMO_DECODE_GPUS=4,5,6,7 ;;
  # Same 2P6D workers; :8000 plain disagg, :8002 conditional disaggregation.
  cdisagg-2p6d) export DYNAMO_PREFILL_GPUS=0,1 DYNAMO_DECODE_GPUS=2,3,4,5,6,7 DYNAMO_DECODE_KV_EVENTS=1 \
                  DYNAMO_EXTRA_FRONTENDS="kv@8002" DYNAMO_EXTRA_FRONTEND_ARGS="--router-conditional-disagg" ;;
  *) printf 'unknown topology %s\n' "${topology}" >&2; exit 2 ;;
esac
# Disaggregated roles: prefill batches long prompts, decode holds many streams.
# The decode worker already streams the first token; don't append it twice.
[[ "${topology}" == *disagg-* ]] && export DYN_VLLM_APPEND_PREFILL_OUTPUT_TOKENS=0
export DYNAMO_PREFILL_EXTRA_ARGS="${DYNAMO_PREFILL_EXTRA_ARGS:---max-num-seqs 32}"
export DYNAMO_DECODE_EXTRA_ARGS="${DYNAMO_DECODE_EXTRA_ARGS:---max-num-seqs 128}"

env_args=()
for n in $(compgen -e | grep -E '^(DYNAMO_|DYN_|VLLM_|ETCD_|NATS_|UCX_)'); do env_args+=(--env "${n}"); done
setsid nohup enroot start --rw \
  --mount "${repo_root}/deploy/edu:/edu" --mount "${DYNAMO_MODEL_CACHE:-${repo_root}/.state/model-cache}:/model-cache" \
  "${env_args[@]}" --env HF_HUB_OFFLINE=1 --env UCX_RCACHE_MAX_UNRELEASED=1024 \
  "${container}" bash /edu/serve.sh >"${log}" 2>&1 </dev/null &
printf 'started %s (%s) -> %s\n' "${topology}" "${profile}" "${log}"
