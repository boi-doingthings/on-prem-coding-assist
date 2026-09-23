#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"

timeout_seconds="${DYNAMO_STARTUP_TIMEOUT:-1200}"
poll_seconds="${DYNAMO_STARTUP_POLL_SECONDS:-10}"
job_id="${SLURM_JOB_ID:-no-slurm-job}"
node="$(hostname -s)"
started_utc="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="${repo_root}/artifacts/restarts/${started_utc}-job-${job_id}-${node}"
log_file="${repo_root}/.state/logs/enroot-disagg.log"
pid_file="${repo_root}/.state/enroot-disagg.pid"

mkdir -p "${run_dir}"

if [[ "${SLURM_CPUS_ON_NODE:-0}" =~ ^[0-9]+$ ]] && \
   (( SLURM_CPUS_ON_NODE < 32 )); then
  printf 'Refusing to start with only %s CPUs; request at least 32.\n' \
    "${SLURM_CPUS_ON_NODE}" >&2
  exit 1
fi

{
  printf 'started_utc=%s\n' "${started_utc}"
  printf 'slurm_job_id=%s\n' "${job_id}"
  printf 'slurm_partition=%s\n' "${SLURM_JOB_PARTITION:-unknown}"
  printf 'node=%s\n' "${node}"
  printf 'cpus_on_node=%s\n' "${SLURM_CPUS_ON_NODE:-unknown}"
  printf 'mem_per_node_mib=%s\n' "${SLURM_MEM_PER_NODE:-unknown}"
  printf 'model=%s\n' "${DYNAMO_MODEL:-nvidia/Qwen3.5-122B-A10B-NVFP4}"
  printf 'served_model=%s\n' "${DYNAMO_SERVED_MODEL:-Qwen/Qwen3.5-122B-A10B}"
  printf 'prefill_gpu=%s\n' "${DYNAMO_PREFILL_GPU:-0}"
  printf 'decode_gpus=%s\n' "${DYNAMO_DECODE_GPUS:-1,2}"
  printf 'runtime_image=%s\n' "${DYNAMO_RUNTIME_IMAGE:-nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.3.0}"
  printf 'dynamo_source_revision=%s\n' \
    "$(git -C "${repo_root}/upstream/dynamo" rev-parse HEAD 2>/dev/null || printf unknown)"
  printf 'lab_revision=%s\n' \
    "$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || printf uncommitted)"
} >"${run_dir}/manifest.env"

nvidia-smi --query-gpu=index,name,uuid,memory.total,memory.used,utilization.gpu \
  --format=csv,noheader >"${run_dir}/gpus-before.csv"
docker info --format \
  'server={{.ServerVersion}} root={{.DockerRootDir}} runtimes={{json .Runtimes}}' \
  >"${run_dir}/docker-info.txt"

"${repo_root}/scripts/prepare-enroot.sh"
"${repo_root}/scripts/start-enroot-disagg.sh" --detach

deadline=$((SECONDS + timeout_seconds))
while true; do
  if curl --silent --show-error --fail --max-time 5 \
      http://127.0.0.1:8000/health >"${run_dir}/health.json" 2>/dev/null && \
     jq --exit-status \
      '(.status == "healthy") and
       ([.instances[]? | select(.component == "prefill" and .endpoint == "generate")] | length >= 1) and
       ([.instances[]? | select(.component == "backend" and .endpoint == "generate")] | length >= 2)' \
      "${run_dir}/health.json" >/dev/null; then
    break
  fi
  if [[ -s "${pid_file}" ]] && ! kill -0 "$(<"${pid_file}")" 2>/dev/null; then
    printf 'Dynamo exited during startup. Last log lines:\n' >&2
    tail -80 "${log_file}" >&2 || true
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    printf 'Timed out after %ss waiting for Dynamo health. Log: %s\n' \
      "${timeout_seconds}" "${log_file}" >&2
    tail -80 "${log_file}" >&2 || true
    exit 1
  fi
  printf 'Waiting for Dynamo on %s (job %s)...\n' "${node}" "${job_id}"
  sleep "${poll_seconds}"
done

"${repo_root}/scripts/smoke-api.sh" | tee "${run_dir}/smoke-api.txt"
"${repo_root}/scripts/configure-pi.sh" | tee "${run_dir}/configure-pi.txt"
PI_DYNAMO_MODEL="${DYNAMO_SERVED_MODEL:-Qwen/Qwen3.5-122B-A10B}" \
  "${repo_root}/scripts/smoke-pi.sh" | tee "${run_dir}/smoke-pi.txt"
nvidia-smi --query-gpu=index,name,memory.used,utilization.gpu \
  --format=csv,noheader >"${run_dir}/gpus-ready.csv"

printf 'Dynamo is ready: http://127.0.0.1:8000\n'
printf 'Restart evidence: %s\n' "${run_dir}"
printf 'Launcher log: %s\n' "${log_file}"
