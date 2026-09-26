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
telemetry_interval="${AIPERF_GPU_TELEMETRY_INTERVAL_SECONDS:-1}"
expected_topology="${AIPERF_EXPECTED_TOPOLOGY:-disagg}"
expected_backends="${AIPERF_EXPECTED_BACKENDS:-2}"
# docker: pinned NGC image (default). local: `pip install aiperf` on the host,
# useful on university clusters without Docker (Apptainer/Enroot/venv).
runner="${AIPERF_RUNNER:-docker}"
base_url="${AIPERF_URL:-http://127.0.0.1:8000}"
extra_inputs="${AIPERF_EXTRA_INPUTS:-temperature:0 ignore_eos:true}"
# Trace replay instead of synthetic ISL/OSL: a mooncake-style JSONL
# ({input_length, output_length, hash_ids}) under .state/traces/. Shared
# hash_ids become shared prompt prefixes, so KV reuse is realistic.
input_file="${AIPERF_INPUT_FILE:-}"
trace_max_osl="${AIPERF_TRACE_MAX_OSL:-1024}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_name="${AIPERF_RUN_NAME:-aiperf-disagg-c${concurrency}}"
artifact_dir="${repo_root}/artifacts/runs/${stamp}-${run_name}"

mkdir -p "${artifact_dir}"

health="$(curl --silent --show-error --fail --max-time 5 \
  "${base_url}/health")"
case "${expected_topology}" in
  disagg)
    health_filter='(.status == "healthy") and
      ([.instances[]? | select(.component == "prefill" and .endpoint == "generate")] | length >= 1) and
      ([.instances[]? | select(.component == "backend" and .endpoint == "generate")] | length >= $backends)'
    topology_description="1P/${expected_backends}D disaggregated"
    ;;
  agg)
    health_filter='(.status == "healthy") and
      ([.instances[]? | select(.component == "prefill" and .endpoint == "generate")] | length == 0) and
      ([.instances[]? | select(.component == "backend" and .endpoint == "generate")] | length >= $backends)'
    topology_description="${expected_backends}-replica aggregated"
    ;;
  any)
    health_filter='(.status == "healthy") and
      ([.instances[]? | select(.endpoint == "generate")] | length >= 1)'
    topology_description="any healthy"
    ;;
  *)
    printf 'Unsupported AIPERF_EXPECTED_TOPOLOGY=%s (use disagg, agg, or any)\n' \
      "${expected_topology}" >&2
    exit 2
    ;;
esac
if ! jq --exit-status --argjson backends "${expected_backends}" \
  "${health_filter}" <<<"${health}" >/dev/null; then
  printf 'Dynamo is not ready with the expected %s topology: %s\n' \
    "${topology_description}" "${health}" >&2
  exit 1
fi
printf '%s\n' "${health}" >"${artifact_dir}/health-before.json"

{
  printf 'started_utc=%s\n' "${stamp}"
  printf 'slurm_job_id=%s\n' "${SLURM_JOB_ID:-unknown}"
  printf 'node=%s\n' "$(hostname -s)"
  printf 'aiperf_runner=%s\n' "${runner}"
  printf 'aiperf_image=%s\n' "${image}"
  printf 'model=%s\n' "${model}"
  printf 'tokenizer=%s\n' "${tokenizer}"
  printf 'expected_topology=%s\n' "${expected_topology}"
  printf 'expected_backends=%s\n' "${expected_backends}"
  printf 'concurrency=%s\n' "${concurrency}"
  printf 'request_count=%s\n' "${request_count}"
  printf 'warmup_request_count=%s\n' "${warmup_count}"
  printf 'isl=%s\n' "${isl}"
  printf 'osl=%s\n' "${osl}"
  printf 'request_timeout_seconds=%s\n' "${timeout}"
  printf 'extra_inputs=%s\n' "${extra_inputs}"
  printf 'seed=%s\n' "${AIPERF_SEED:-42}"
  printf 'aiperf_extra_args=%s\n' "${AIPERF_EXTRA_ARGS:-}"
  printf 'input_file=%s\n' "${input_file:-synthetic}"
  printf 'trace_max_osl=%s\n' "${trace_max_osl}"
  printf 'gpus=%s\n' "${AIPERF_GPUS:-unknown}"
  printf 'series=%s\n' "${AIPERF_SERIES:-${run_name}}"
} >"${artifact_dir}/manifest.env"

if [[ "${runner}" == "docker" ]]; then
  docker image inspect "${image}" --format '{{json .RepoDigests}}' \
    >"${artifact_dir}/image-digests.json"
else
  aiperf --version >"${artifact_dir}/aiperf-version.txt" 2>&1 || true
fi

printf 'AIPerf artifacts: %s\n' "${artifact_dir}"
(
  printf 'timestamp,index,name,memory_used_mib,memory_total_mib,gpu_util_pct,memory_util_pct,power_w,sm_clock_mhz,memory_clock_mhz\n'
  while true; do
    sample_time="$(date '+%Y-%m-%dT%H:%M:%S.%N%:z')"
    nvidia-smi \
      --query-gpu=index,name,memory.used,memory.total,utilization.gpu,utilization.memory,power.draw,clocks.sm,clocks.mem \
      --format=csv,noheader,nounits | while IFS= read -r sample; do
        printf '%s,%s\n' "${sample_time}" "${sample}"
      done
    sleep "${telemetry_interval}"
  done
) >"${artifact_dir}/host-gpu-telemetry.csv" 2>"${artifact_dir}/host-gpu-telemetry.err" &
sampler_pid=$!

cleanup_sampler() {
  kill "${sampler_pid}" 2>/dev/null || true
  wait "${sampler_pid}" 2>/dev/null || true
}
trap cleanup_sampler EXIT INT TERM

read -ra extra_input_args <<<"${extra_inputs}"
profile_args=(
  profile
  --model "${model}"
  --tokenizer "${tokenizer}"
  --tokenizer-trust-remote-code
  --url "${base_url}"
  --endpoint-type chat
  --streaming
  --use-server-token-count
  --extra-inputs "${extra_input_args[@]}"
  --concurrency "${concurrency}"
  --request-count "${request_count}"
  --workers-max "${concurrency}"
  --random-seed "${AIPERF_SEED:-42}"
  --ui simple
  --request-timeout-seconds "${timeout}"
)
# Extra AIPerf flags (e.g. multi-turn sessions:
#   --num-sessions 48 --session-turns-mean 6 --user-context-prompt-length 20000)
read -ra aiperf_extra <<<"${AIPERF_EXTRA_ARGS:-}"
profile_args+=("${aiperf_extra[@]}")
# AIPerf requires warmup > 0 when given; 0 means "no warmup" (cold-cache runs).
if (( warmup_count > 0 )); then
  profile_args+=(--warmup-request-count "${warmup_count}" --warmup-concurrency 1)
fi
trace_mount=()
if [[ -n "${input_file}" ]]; then
  trace_dir="$(cd "$(dirname "${input_file}")" && pwd)"
  trace_name="$(basename "${input_file}")"
  trace_mount=(--volume "${trace_dir}:/traces:ro")
  trace_path="/traces/${trace_name}"
  [[ "${runner}" != "docker" ]] && trace_path="${trace_dir}/${trace_name}"
  profile_args+=(--input-file "${trace_path}" --custom-dataset-type mooncake_trace
                 --dataset-sampling-strategy sequential
                 --synthesis-max-osl "${trace_max_osl}" --synthesis-max-isl 262000)
else
  profile_args+=(--isl "${isl}" --isl-stddev 0 --osl "${osl}" --osl-stddev 0)
fi

set +e
if [[ "${runner}" == "docker" ]]; then
  docker run --rm \
    --network host \
    --user 0:0 \
    --env HOME=/tmp \
    --env HF_HOME=/model-cache \
    --env HF_HUB_DISABLE_XET=1 \
    --volume "${model_cache}:/model-cache:ro" \
    --volume "${artifact_dir}:/artifacts" \
    "${trace_mount[@]}" \
    --entrypoint aiperf \
    "${image}" \
    "${profile_args[@]}" --artifact-dir /artifacts
else
  HF_HOME="${model_cache}" aiperf "${profile_args[@]}" \
    --artifact-dir "${artifact_dir}"
fi
status=$?
set -e

cleanup_sampler
trap - EXIT INT TERM
exit "${status}"
