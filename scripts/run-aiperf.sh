#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"

image="${AIPERF_IMAGE:-nvcr.io/nvidia/ai-dynamo/aiperf:0.12.0}"
model="${DYNAMO_SERVED_MODEL:-Qwen/Qwen3.5-122B-A10B}"
tokenizer="${DYNAMO_MODEL:-nvidia/Qwen3.5-122B-A10B-NVFP4}"
model_cache="${DYNAMO_MODEL_CACHE:-${repo_root}/.state/model-cache}"
concurrency="${AIPERF_CONCURRENCY:-1}"
request_count="${AIPERF_REQUEST_COUNT:-16}"
warmup_count="${AIPERF_WARMUP_REQUEST_COUNT:-3}"
isl="${AIPERF_ISL:-800}"
osl="${AIPERF_OSL:-64}"
timeout="${AIPERF_REQUEST_TIMEOUT_SECONDS:-300}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_name="${AIPERF_RUN_NAME:-aiperf-disagg-c${concurrency}}"
artifact_dir="${repo_root}/artifacts/runs/${stamp}-${run_name}"

mkdir -p "${artifact_dir}"

health="$(curl --silent --show-error --fail --max-time 5 \
  http://127.0.0.1:8000/health)"
if ! jq --exit-status \
  '(.status == "healthy") and
   ([.instances[]? | select(.component == "prefill" and .endpoint == "generate")] | length >= 1) and
   ([.instances[]? | select(.component == "backend" and .endpoint == "generate")] | length >= 2)' \
  <<<"${health}" >/dev/null; then
  printf 'Dynamo is not ready with the expected 1P/2D topology: %s\n' \
    "${health}" >&2
  exit 1
fi
printf '%s\n' "${health}" >"${artifact_dir}/health-before.json"

{
  printf 'started_utc=%s\n' "${stamp}"
  printf 'slurm_job_id=%s\n' "${SLURM_JOB_ID:-unknown}"
  printf 'node=%s\n' "$(hostname -s)"
  printf 'aiperf_image=%s\n' "${image}"
  printf 'model=%s\n' "${model}"
  printf 'tokenizer=%s\n' "${tokenizer}"
  printf 'concurrency=%s\n' "${concurrency}"
  printf 'request_count=%s\n' "${request_count}"
  printf 'warmup_request_count=%s\n' "${warmup_count}"
  printf 'isl=%s\n' "${isl}"
  printf 'osl=%s\n' "${osl}"
  printf 'request_timeout_seconds=%s\n' "${timeout}"
} >"${artifact_dir}/manifest.env"

docker image inspect "${image}" --format '{{json .RepoDigests}}' \
  >"${artifact_dir}/image-digests.json"

printf 'AIPerf artifacts: %s\n' "${artifact_dir}"
docker run --rm \
  --network host \
  --user 0:0 \
  --env HOME=/tmp \
  --env HF_HOME=/model-cache \
  --env HF_HUB_DISABLE_XET=1 \
  --volume "${model_cache}:/model-cache:ro" \
  --volume "${artifact_dir}:/artifacts" \
  --entrypoint aiperf \
  "${image}" \
  profile \
  --model "${model}" \
  --tokenizer "${tokenizer}" \
  --tokenizer-trust-remote-code \
  --url http://127.0.0.1:8000 \
  --endpoint-type chat \
  --streaming \
  --use-server-token-count \
  --extra-inputs temperature:0 ignore_eos:true \
  --isl "${isl}" \
  --isl-stddev 0 \
  --osl "${osl}" \
  --osl-stddev 0 \
  --concurrency "${concurrency}" \
  --warmup-request-count "${warmup_count}" \
  --warmup-concurrency 1 \
  --request-count "${request_count}" \
  --workers-max "${concurrency}" \
  --random-seed 42 \
  --ui simple \
  --artifact-dir /artifacts \
  --request-timeout-seconds "${timeout}"
