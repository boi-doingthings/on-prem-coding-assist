#!/usr/bin/env bash
# Multi-model serving demo: two models behind ONE Dynamo frontend (:8000).
# Model A (with frontend) on GPUs 0-3; model B (workers only, joining through
# etcd) on GPUs 4-7. Defaults: Nemotron 3.5 Lightning teacher vs the pruned
# student from ../nemotron-3.5-lightning-artifacts (workshop-contents repo).
# Requires etcd + NATS: docker compose -f deploy/local/compose.yaml up -d nats etcd
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/scripts/env.sh"
source "${repo_root}/scripts/enroot-env.sh"

art="${PAIR_ARTIFACTS:-$(cd "${repo_root}/.." && pwd)/nemotron-3.5-lightning-artifacts}"
model_a="${PAIR_MODEL_A:-/art/hf-cache/hub/models--nvidia--NVIDIA-Nemotron-3.5-Lightning-30B-A3B-BF16/snapshots/d468880b6ad3c6e0d21377ce7242adaea4cc884d}"
name_a="${PAIR_NAME_A:-nemotron-3.5-lightning-teacher}"
model_b="${PAIR_MODEL_B:-/art/pruned/student-a2.5b}"
name_b="${PAIR_NAME_B:-nemotron-3.5-lightning-pruned-a2.5b}"
container="${SHOWCASE_CONTAINER:-dynamo-vllm-15}"

common=(--env DYNAMO_DISCOVERY=etcd --env ETCD_ENDPOINTS=http://127.0.0.1:2379 --env NATS_SERVER=nats://127.0.0.1:4222
        --env DYNAMO_TOOL_PARSER=nemotron_nano --env DYNAMO_REASONING_PARSER=nemotron_nano
        --env DYNAMO_MAX_MODEL_LEN="${PAIR_MAX_MODEL_LEN:-65536}"
        --env DYNAMO_EXTRA_ARGS="${PAIR_EXTRA_ARGS:---reasoning-parser nemotron_v3 --max-num-seqs 256 --mamba-ssm-cache-dtype float16 --gpu-memory-utilization 0.85}"
        --env HF_HUB_OFFLINE=1 --mount "${repo_root}/deploy/edu:/edu" --mount "${art}:/art")

# Each model needs its own Dynamo namespace (one model per endpoint); the
# frontend discovers every namespace by default.
launch() {  # served name, model path, gpus, frontend (1/0), port offset, log, namespace
  setsid nohup enroot start --rw "${common[@]}" --env DYNAMO_MODEL="$2" --env DYNAMO_SERVED_MODEL="$1" \
    --env DYNAMO_GPUS="$3" --env DYNAMO_FRONTEND="$4" --env DYNAMO_PORT_OFFSET="$5" --env DYN_NAMESPACE="$7" \
    "${container}" bash /edu/serve.sh >"$6" 2>&1 </dev/null &
}

mkdir -p "${repo_root}/.state/logs"
[[ "${PAIR_ONLY_B:-0}" == "1" ]] || launch "${name_a}" "${model_a}" "${PAIR_GPUS_A:-0,1,2,3}" 1 0 "${repo_root}/.state/logs/pair-a.log" dynamo
[[ "${PAIR_ONLY_B:-0}" == "1" ]] ||
sleep 20
launch "${name_b}" "${model_b}" "${PAIR_GPUS_B:-4,5,6,7}" 0 10 "${repo_root}/.state/logs/pair-b.log" dynamo-b
printf 'started %s and %s behind :8000 (logs: .state/logs/pair-a.log, pair-b.log)\n' "${name_a}" "${name_b}"
