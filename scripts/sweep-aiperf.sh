#!/usr/bin/env bash
# Concurrency sweep for one deployment, stopping at the first failed point.
#
# The lab found that some engine configurations wedge (stop returning bytes)
# past a concurrency threshold instead of degrading gracefully. A sweep must
# therefore stop, report the boundary, and leave recovery to the operator
# rather than hammer a wedged server and record misleading averages.
#
# Workload profiles (nominal ISL/OSL; set AIPERF_ISL/AIPERF_OSL to override):
#   chat          800 /   256   Q&A, tutoring, Open WebUI traffic
#   coding-agent  16000 / 512   agent turn: long repo/tool context, short edit
#   long-context  64000 / 256   whole-file / whole-repo reasoning
#   decode-heavy  800 /  2048   explanations, reasoning traces, report writing
#
# Usage:
#   SWEEP_PROFILE=coding-agent SWEEP_CONCURRENCIES="1 2 4 8 16" \
#   AIPERF_GPUS=4 AIPERF_EXPECTED_TOPOLOGY=any ./scripts/sweep-aiperf.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${SWEEP_PROFILE:-chat}"
concurrencies="${SWEEP_CONCURRENCIES:-1 2 4 8 16 32}"
requests_per_slot="${SWEEP_REQUESTS_PER_CONCURRENCY:-8}"
min_requests="${SWEEP_MIN_REQUESTS:-16}"
label="${SWEEP_LABEL:-$(basename "${DYNAMO_SERVED_MODEL:-model}")}"

case "${profile}" in
  chat)         isl=800;   osl=256 ;;
  coding-agent) isl=16000; osl=512 ;;
  long-context) isl=64000; osl=256 ;;
  decode-heavy) isl=800;   osl=2048 ;;
  *) printf 'Unknown SWEEP_PROFILE=%s\n' "${profile}" >&2; exit 2 ;;
esac
isl="${AIPERF_ISL:-${isl}}"
osl="${AIPERF_OSL:-${osl}}"
series="${label}-${profile}"

run_dirs=()
for c in ${concurrencies}; do
  count=$(( c * requests_per_slot ))
  (( count < min_requests )) && count="${min_requests}"
  printf '\n=== %s: concurrency %s, %s requests, ISL %s / OSL %s ===\n' \
    "${series}" "${c}" "${count}" "${isl}" "${osl}"
  set +e
  output="$(AIPERF_CONCURRENCY="${c}" AIPERF_REQUEST_COUNT="${count}" \
    AIPERF_ISL="${isl}" AIPERF_OSL="${osl}" AIPERF_SERIES="${series}" \
    AIPERF_RUN_NAME="sweep-${series}-c${c}" \
    "${repo_root}/scripts/run-aiperf.sh" 2>&1 | tee /dev/stderr)"
  status=$?
  set -e
  dir="$(sed -n 's/^AIPerf artifacts: //p' <<<"${output}" | tail -1)"
  [[ -n "${dir}" ]] && run_dirs+=("${dir}")
  export_file="${dir}/profile_export_aiperf.json"
  if (( status != 0 )) || [[ ! -f "${export_file}" ]] || \
     ! jq --exit-status --argjson n "${count}" \
       '(.request_count.avg // 0) >= $n and ((.error_summary // []) | length == 0)' \
       "${export_file}" >/dev/null; then
    printf '\nConcurrency %s failed; stopping the sweep. Check the server before reusing it:\n' "${c}" >&2
    printf '  curl -s localhost:8000/health | jq .; send one c1 request; restart if it hangs.\n' >&2
    break
  fi
done

(( ${#run_dirs[@]} )) || exit 1
out="${repo_root}/results/sweeps/$(date -u +%Y%m%d)-${series}"
python3 "${repo_root}/tools/summarize-aiperf.py" "${run_dirs[@]}" \
  --series-key series --title "${series}" --out "${out}"
