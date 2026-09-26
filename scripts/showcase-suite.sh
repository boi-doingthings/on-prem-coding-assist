#!/usr/bin/env bash
# Run the standard showcase workloads against the topology currently serving
# on :8000 and label the results with a prefix.
#   ./scripts/showcase-suite.sh d2p6d 400     # label prefix, seed base
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${1:?label prefix}" seed="${2:?seed base}"
log="${repo_root}/.state/logs/suite-${prefix}.log"
: >"${log}"
for c in ${SUITE_TRACE_CONCURRENCY:-64 128}; do
  seed=$((seed + 1))
  echo "=== ${prefix} trace c${c} seed ${seed} $(date -u +%T)" >>"${log}"
  SHOWCASE_LABEL="${prefix}" SHOWCASE_SEED="${seed}" SHOWCASE_CONCURRENCY="${c}" SHOWCASE_REQUESTS=800 \
    "${repo_root}/scripts/showcase-trace.sh" >>"${log}" 2>/dev/null
done
for c in ${SUITE_MT_CONCURRENCY:-32 64}; do
  seed=$((seed + 1))
  echo "=== mt-${prefix} c${c} seed ${seed} $(date -u +%T)" >>"${log}"
  AIPERF_ISL=1000 AIPERF_OSL=300 \
  AIPERF_EXTRA_ARGS="--num-sessions 128 --num-dataset-entries 128 --session-turns-mean 6 --session-turns-stddev 0 --shared-system-prompt-length 4000 --user-context-prompt-length 30000" \
  SHOWCASE_TRACE=none SHOWCASE_LABEL="mt-${prefix}" SHOWCASE_SEED="${seed}" SHOWCASE_CONCURRENCY="${c}" \
  SHOWCASE_REQUESTS=768 "${repo_root}/scripts/showcase-trace.sh" >>"${log}" 2>/dev/null
done
echo "SUITE DONE $(date -u +%T)" >>"${log}"
grep -E "===|cache:|SUITE" "${log}"
