#!/usr/bin/env bash
# Serve an open model with Dynamo on one Slurm node (any NVIDIA GPU tier).
#
#   sbatch --gres=gpu:4 --cpus-per-task=64 --mem=0 --time=08:00:00 \
#     --export=ALL,EDU_PROFILE=config/edu-models/qwen3.6-35b-a3b-fp8.env \
#     deploy/edu/serve.sbatch
#
# Designed for "idle-cycle" serving: submit to a preemptible/low-priority QOS
# with --requeue so research jobs always win; the model cache on shared
# storage makes a restart on another node cost minutes, not a re-download.
#
# EDU_RUNTIME selects how the container is started:
#   pyxis     srun --container-image (NVIDIA Pyxis/Enroot plugin)  [default]
#   apptainer apptainer exec --nv  (common on university HPC)
#   enroot    enroot start (no Slurm plugin needed)
#SBATCH --job-name=dynamo-edu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --exclusive
#SBATCH --requeue
#SBATCH --signal=B:TERM@120
#SBATCH --output=dynamo-edu-%j.log
set -euo pipefail

repo_root="${EDU_REPO_ROOT:-${SLURM_SUBMIT_DIR:-$(pwd)}}"
profile="${EDU_PROFILE:?set EDU_PROFILE=config/edu-models/<model>.env}"
# Export everything the profile sets (DYNAMO_*, and engine env such as VLLM_*)
# so Pyxis/Apptainer containers inherit it.
set -a
# shellcheck disable=SC1090
source "${repo_root}/${profile}"
set +a

runtime="${EDU_RUNTIME:-pyxis}"
image="${DYNAMO_RUNTIME_IMAGE:-nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.5.0}"
model_cache="${DYNAMO_MODEL_CACHE:-${repo_root}/.state/model-cache}"
cache_root="${DYNAMO_CACHE_ROOT:-${repo_root}/.state/compile-cache/${SLURM_JOB_PARTITION:-local}}"
port="${DYNAMO_HTTP_PORT:-8000}"
mkdir -p "${model_cache}" "${cache_root}"

# Only forward the variables the launcher reads; never echo secret values.
env_names=(DYNAMO_MODEL DYNAMO_SERVED_MODEL DYNAMO_BACKEND DYNAMO_GPUS DYNAMO_TP
           DYNAMO_TOOL_PARSER DYNAMO_REASONING_PARSER DYNAMO_MAX_MODEL_LEN
           DYNAMO_ROUTER_MODE DYNAMO_EXTRA_ARGS DYNAMO_HTTP_PORT DYNAMO_DISCOVERY
           ETCD_ENDPOINTS NATS_SERVER HF_TOKEN)
export DYNAMO_CACHE_ROOT=/compile-cache HF_HOME=/model-cache

cat <<INFO
== Dynamo edu serve: job ${SLURM_JOB_ID:-local} on $(hostname -s)
   model   : ${DYNAMO_SERVED_MODEL:-${DYNAMO_MODEL}}
   image   : ${image}
   runtime : ${runtime}
   endpoint: http://$(hostname -f):${port}/v1
   tunnel  : ssh -N -L ${port}:$(hostname -s):${port} ${USER}@<login-node>
INFO
nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader

case "${runtime}" in
  pyxis)
    srun --container-image="${image}" \
      --container-mounts="${repo_root}/deploy/edu:/edu,${model_cache}:/model-cache,${cache_root}:/compile-cache" \
      --container-writable --no-container-mount-home \
      bash /edu/serve.sh
    ;;
  apptainer)
    sif="${EDU_SIF:-${repo_root}/.state/dynamo-runtime.sif}"
    [[ -f "${sif}" ]] || apptainer pull "${sif}" "docker://${image}"
    apptainer exec --nv --writable-tmpfs \
      --bind "${repo_root}/deploy/edu:/edu,${model_cache}:/model-cache,${cache_root}:/compile-cache" \
      "${sif}" bash /edu/serve.sh
    ;;
  enroot)
    sqsh="${EDU_SQSH:-${repo_root}/.state/enroot/images/$(basename "${image//:/-}").sqsh}"
    [[ -f "${sqsh}" ]] || enroot import --output "${sqsh}" "docker://${image/\//#}"
    name="dynamo-edu-${SLURM_JOB_ID:-$$}"
    enroot create --force --name "${name}" "${sqsh}"
    env_args=()
    # Enroot does not inherit the host env: forward the launcher's variables
    # plus any engine variables the profile set.
    mapfile -t profile_env < <(compgen -e | grep -E '^(VLLM_|SGLANG_|NCCL_|UCX_|FLASHINFER_)' || true)
    for n in "${env_names[@]}" "${profile_env[@]}" DYNAMO_CACHE_ROOT HF_HOME; do
      [[ -n "${!n:-}" ]] && env_args+=(--env "${n}")
    done
    enroot start --rw "${env_args[@]}" \
      --mount "${repo_root}/deploy/edu:/edu" --mount "${model_cache}:/model-cache" \
      --mount "${cache_root}:/compile-cache" "${name}" bash /edu/serve.sh
    ;;
  *)
    printf 'Unknown EDU_RUNTIME=%s\n' "${runtime}" >&2
    exit 2
    ;;
esac
