#!/usr/bin/env bash
# Portable single-node Dynamo launcher for workshops on any NVIDIA GPU tier.
#
# Runs INSIDE a Dynamo runtime container (vllm-runtime or sglang-runtime).
# Uses file-based discovery and the TCP request plane, so it needs no etcd or
# NATS: one container, one node, one command. Launches one KV-aware frontend
# and N aggregated worker replicas, each spanning DYNAMO_TP GPUs.
#
# Configure through a model profile (config/edu-models/*.env) or environment:
#   DYNAMO_MODEL           HF id or local path of the checkpoint
#   DYNAMO_SERVED_MODEL    name clients send in "model" (default: DYNAMO_MODEL)
#   DYNAMO_BACKEND         vllm | sglang                       (default vllm)
#   DYNAMO_GPUS            comma list of GPU indices           (default: all)
#   DYNAMO_TP              GPUs per replica                    (default 1)
#   DYNAMO_TOOL_PARSER     e.g. qwen3_coder, harmony, hermes   (default none)
#   DYNAMO_REASONING_PARSER e.g. qwen3, gpt_oss, nemotron_deci (default none)
#   DYNAMO_MAX_MODEL_LEN   context cap, e.g. 65536              (default model max)
#   DYNAMO_ROUTER_MODE     kv | round-robin | random           (default kv)
#   DYNAMO_EXTRA_ARGS      extra engine flags, space separated
#   DYNAMO_HTTP_PORT       frontend port                       (default 8000)
#   DYNAMO_DISCOVERY       file | etcd                         (default file)
#   DYNAMO_FRONTEND        1 | 0  (0 = workers only, joining an existing
#                          frontend through etcd: multi-model serving)
#   DYNAMO_PORT_OFFSET     shift worker ports when a second launcher shares the node
#   DYNAMO_EXTRA_FRONTENDS extra routers on the same workers, e.g.
#                          "round-robin@8001 random@8002" (A/B routing demos)
#
# Disaggregated prefill/decode (NIXL KV transfer) instead of DYNAMO_GPUS:
#   DYNAMO_PREFILL_GPUS    e.g. 0,1        (groups of DYNAMO_TP GPUs per worker)
#   DYNAMO_DECODE_GPUS     e.g. 2,3,4,5,6,7
#   DYNAMO_PREFILL_EXTRA_ARGS / DYNAMO_DECODE_EXTRA_ARGS  role-specific flags
#   DYNAMO_DECODE_KV_EVENTS=1   decode workers also publish KV events (needed
#                               for --router-conditional-disagg)
#   DYNAMO_EXTRA_FRONTEND_ARGS  extra flags for DYNAMO_EXTRA_FRONTENDS, e.g.
#                               "--router-conditional-disagg"
#
# Discovery: `file` needs nothing else and is what workshops use. Upstream docs
# state that KV events for KV-aware routing and the planner require etcd+NATS;
# with vllm-runtime 1.3.0 the kv router still ran and scored workers in file
# mode, but for routing experiments (Lab 5) start etcd+NATS
# (deploy/local/compose.yaml) and set DYNAMO_DISCOVERY=etcd, ETCD_ENDPOINTS
# and NATS_SERVER so prefix-cache events are guaranteed to reach the router.
set -euo pipefail

trap 'status=$?; trap - EXIT; kill 0 2>/dev/null || true; exit "$status"' EXIT

model="${DYNAMO_MODEL:?set DYNAMO_MODEL or source a config/edu-models profile}"
served_model="${DYNAMO_SERVED_MODEL:-${model}}"
backend="${DYNAMO_BACKEND:-vllm}"
tp="${DYNAMO_TP:-1}"
router_mode="${DYNAMO_ROUTER_MODE:-kv}"
http_port="${DYNAMO_HTTP_PORT:-8000}"
block_size="${DYNAMO_KV_BLOCK_SIZE:-64}"

# Build the worker list as "role:gpu,gpu" entries.
workers=()
add_workers() {  # role, comma-separated GPU list
  local role="$1" list=() i
  IFS=',' read -ra list <<<"$2"
  if (( ${#list[@]} % tp != 0 )); then
    printf '%s GPUs (%s) are not a multiple of DYNAMO_TP=%s\n' "${role}" "$2" "${tp}" >&2
    exit 2
  fi
  for (( i = 0; i < ${#list[@]}; i += tp )); do
    workers+=("${role}:$(IFS=,; echo "${list[*]:i:tp}")")
  done
}
if [[ -n "${DYNAMO_PREFILL_GPUS:-}" || -n "${DYNAMO_DECODE_GPUS:-}" ]]; then
  : "${DYNAMO_PREFILL_GPUS:?disaggregated mode needs DYNAMO_PREFILL_GPUS}"
  : "${DYNAMO_DECODE_GPUS:?disaggregated mode needs DYNAMO_DECODE_GPUS}"
  add_workers prefill "${DYNAMO_PREFILL_GPUS}"
  add_workers decode "${DYNAMO_DECODE_GPUS}"
  topology="disagg ${DYNAMO_PREFILL_GPUS} -> ${DYNAMO_DECODE_GPUS}"
else
  if [[ -z "${DYNAMO_GPUS:-}" ]]; then
    DYNAMO_GPUS="$(nvidia-smi --query-gpu=index --format=csv,noheader | paste -sd, -)"
  fi
  add_workers agg "${DYNAMO_GPUS}"
  topology="agg on GPUs ${DYNAMO_GPUS}"
fi

# Keep compile/autotune caches off shared home directories; point them at a
# persistent path (DYNAMO_CACHE_ROOT) to avoid paying warmup on every restart.
cache_root="${DYNAMO_CACHE_ROOT:-/tmp/dynamo-cache}"
export HF_HOME="${HF_HOME:-/model-cache}"
export TRITON_CACHE_DIR="${cache_root}/triton"
export VLLM_CACHE_ROOT="${cache_root}/vllm"
export FLASHINFER_WORKSPACE_BASE="${cache_root}/flashinfer"
export PYTHONHASHSEED=0
mkdir -p "${cache_root}"

discovery_args=()
case "${DYNAMO_DISCOVERY:-file}" in
  file)
    export DYN_FILE_KV="${cache_root}/discovery-$$"
    mkdir -p "${DYN_FILE_KV}"
    discovery_args=(--discovery-backend file)
    ;;
  etcd) ;;  # uses ETCD_ENDPOINTS / NATS_SERVER from the environment
  *) printf 'Unsupported DYNAMO_DISCOVERY=%s (file or etcd)\n' "${DYNAMO_DISCOVERY}" >&2; exit 2 ;;
esac

frontend_args=("${discovery_args[@]}" --router-mode "${router_mode}"
               --http-port "${http_port}" --kv-cache-block-size "${block_size}")
[[ "${router_mode}" == "kv" ]] && frontend_args+=(--router-kv-events)

printf 'Dynamo edu launcher: %s (%s) | backend=%s | %s worker(s) x TP%s | %s | router=%s\n' \
  "${served_model}" "${model}" "${backend}" "${#workers[@]}" "${tp}" "${topology}" "${router_mode}"

if [[ "${DYNAMO_FRONTEND:-1}" == "1" ]]; then
  python3 -m dynamo.frontend "${frontend_args[@]}" &
fi
port_offset="${DYNAMO_PORT_OFFSET:-0}"
for spec in ${DYNAMO_EXTRA_FRONTENDS:-}; do
  mode="${spec%@*}" port="${spec#*@}"
  extra_frontend=("${discovery_args[@]}" --router-mode "${mode}" --http-port "${port}"
                  --kv-cache-block-size "${block_size}")
  [[ "${mode}" == "kv" ]] && extra_frontend+=(--router-kv-events)
  read -ra extra_frontend_flags <<<"${DYNAMO_EXTRA_FRONTEND_ARGS:-}"
  extra_frontend+=("${extra_frontend_flags[@]}")
  printf '  extra frontend: router=%s on port %s %s\n' "${mode}" "${port}" "${DYNAMO_EXTRA_FRONTEND_ARGS:-}"
  python3 -m dynamo.frontend "${extra_frontend[@]}" &
done

read -ra extra_args <<<"${DYNAMO_EXTRA_ARGS:-}"
# Dynamo-native parsers are worker flags; the frontend applies them per model.
parser_args=()
[[ -n "${DYNAMO_TOOL_PARSER:-}" ]] && parser_args+=(--dyn-tool-call-parser "${DYNAMO_TOOL_PARSER}")
[[ -n "${DYNAMO_REASONING_PARSER:-}" ]] && parser_args+=(--dyn-reasoning-parser "${DYNAMO_REASONING_PARSER}")
read -ra prefill_extra <<<"${DYNAMO_PREFILL_EXTRA_ARGS:-}"
read -ra decode_extra <<<"${DYNAMO_DECODE_EXTRA_ARGS:-}"
nixl='"kv_connector":"NixlConnector","kv_connector_extra_config":{"num_threads":8}'
for (( r = 0; r < ${#workers[@]}; r++ )); do
  role="${workers[r]%%:*}"
  replica_gpus="${workers[r]#*:}"
  event_port=$(( 5557 + port_offset + r ))
  export DYN_SYSTEM_PORT=$(( 18081 + port_offset + r ))
  export VLLM_NIXL_SIDE_CHANNEL_PORT=$(( 21096 + port_offset + r ))
  role_args=()
  kv_events=(--kv-events-config "{\"publisher\":\"zmq\",\"topic\":\"kv-events\",\"endpoint\":\"tcp://*:${event_port}\",\"enable_kv_cache_events\":true}")
  case "${role}" in
    prefill) role_args=(--disaggregation-mode prefill --kv-transfer-config "{${nixl},\"kv_role\":\"kv_producer\"}"
                        "${prefill_extra[@]}") ;;
    # Decode workers receive KV over NIXL; the router scores prefill workers.
    decode)  role_args=(--disaggregation-mode decode --kv-transfer-config "{${nixl},\"kv_role\":\"kv_consumer\"}"
                        "${decode_extra[@]}")
             [[ "${DYNAMO_DECODE_KV_EVENTS:-0}" == "1" ]] || kv_events=() ;;
  esac
  case "${backend}" in
    vllm)
      worker_args=(--model "${model}" --served-model-name "${served_model}"
                   --tensor-parallel-size "${tp}" --block-size "${block_size}"
                   --enable-prefix-caching --trust-remote-code
                   "${discovery_args[@]}" "${kv_events[@]}")
      [[ -n "${DYNAMO_MAX_MODEL_LEN:-}" ]] && worker_args+=(--max-model-len "${DYNAMO_MAX_MODEL_LEN}")
      CUDA_VISIBLE_DEVICES="${replica_gpus}" \
        python3 -m dynamo.vllm "${worker_args[@]}" "${parser_args[@]}" "${extra_args[@]}" "${role_args[@]}" &
      ;;
    sglang)
      if [[ "${role}" != "agg" ]]; then
        printf 'Disaggregated mode is implemented for the vLLM backend only\n' >&2
        exit 2
      fi
      worker_args=(--model-path "${model}" --served-model-name "${served_model}"
                   --tp "${tp}" --page-size "${block_size}" --trust-remote-code
                   "${discovery_args[@]}" --kv-events-config
                   "{\"publisher\":\"zmq\",\"topic\":\"kv-events\",\"endpoint\":\"tcp://*:${event_port}\"}")
      [[ -n "${DYNAMO_MAX_MODEL_LEN:-}" ]] && worker_args+=(--context-length "${DYNAMO_MAX_MODEL_LEN}")
      CUDA_VISIBLE_DEVICES="${replica_gpus}" \
        python3 -m dynamo.sglang "${worker_args[@]}" "${parser_args[@]}" "${extra_args[@]}" &
      ;;
    *)
      printf 'Unsupported DYNAMO_BACKEND=%s (vllm or sglang)\n' "${backend}" >&2
      exit 2
      ;;
  esac
  printf '  worker %s (%s) -> GPUs %s (system port %s)\n' \
    "${r}" "${role}" "${replica_gpus}" "${DYN_SYSTEM_PORT}"
done

wait -n
