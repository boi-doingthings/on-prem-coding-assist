#!/usr/bin/env bash
# Replay the agentic coding trace against one router/topology and record the
# engine prefix-cache hit rate for exactly that run.
#
#   SHOWCASE_LABEL=agg8-kv SHOWCASE_URL=http://127.0.0.1:8000 SHOWCASE_WORKERS=8 \
#   SHOWCASE_SEED=101 SHOWCASE_CONCURRENCY=64 SHOWCASE_REQUESTS=600 ./scripts/showcase-trace.sh
#
# A fresh SHOWCASE_SEED gives identical prefix *structure* with new token
# content, so every run starts with a cold cache without restarting engines.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
label="${SHOWCASE_LABEL:?}" url="${SHOWCASE_URL:-http://127.0.0.1:8000}"
workers="${SHOWCASE_WORKERS:-8}" gpus="${SHOWCASE_GPUS:-8}"
trace="${SHOWCASE_TRACE:-${repo_root}/.state/traces/agentic-le250k.jsonl}"

cache_counters() {  # prints "queries hits" summed over worker system ports
  local q=0 h=0 i port body
  for (( i = 0; i < workers; i++ )); do
    port=$(( 18081 + i ))
    body="$(curl -s -m 5 "http://127.0.0.1:${port}/metrics" || true)"
    q=$(awk -v q="$q" '/^vllm:prefix_cache_queries_total/ {q += $NF} END {printf "%.0f", q}' <<<"${body}")
    h=$(awk -v h="$h" '/^vllm:prefix_cache_hits_total/ {h += $NF} END {printf "%.0f", h}' <<<"${body}")
  done
  printf '%s %s\n' "$q" "$h"
}

read -r q0 h0 < <(cache_counters)
# SHOWCASE_TRACE=none switches to synthetic mode (AIPERF_ISL/OSL/EXTRA_ARGS).
[[ "${trace}" == "none" ]] && trace=""
output="$(AIPERF_URL="${url}" AIPERF_INPUT_FILE="${trace}" AIPERF_SEED="${SHOWCASE_SEED:-101}" \
  AIPERF_CONCURRENCY="${SHOWCASE_CONCURRENCY:-64}" AIPERF_REQUEST_COUNT="${SHOWCASE_REQUESTS:-600}" \
  AIPERF_WARMUP_REQUEST_COUNT=0 AIPERF_REQUEST_TIMEOUT_SECONDS="${SHOWCASE_TIMEOUT:-900}" \
  AIPERF_TRACE_MAX_OSL="${SHOWCASE_MAX_OSL:-1024}" AIPERF_GPUS="${gpus}" AIPERF_SERIES="${label}" \
  AIPERF_RUN_NAME="showcase-${label}-c${SHOWCASE_CONCURRENCY:-64}" \
  AIPERF_EXPECTED_TOPOLOGY=any "${repo_root}/scripts/run-aiperf.sh" 2>&1 | tee /dev/stderr)" || true
read -r q1 h1 < <(cache_counters)
dir="$(sed -n 's/^AIPerf artifacts: //p' <<<"${output}" | tail -1)"
python3 - "${dir}" "$((q1 - q0))" "$((h1 - h0))" <<'PY'
import json, pathlib, sys
d, q, h = pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
stats = {"prefix_cache_queried_tokens": q, "prefix_cache_hit_tokens": h,
         "prefix_cache_hit_rate": round(h / q, 4) if q else None}
(d / "cache-stats.json").write_text(json.dumps(stats, indent=2) + "\n")
print("cache:", stats)
PY
