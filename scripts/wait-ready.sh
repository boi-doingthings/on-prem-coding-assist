#!/usr/bin/env bash
# Wait until the frontend lists N generate endpoints (prefill + backend), or fail.
#   ./scripts/wait-ready.sh 8 [port] [timeout_seconds] [log_file]
set -uo pipefail
want="${1:?number of workers}" port="${2:-8000}" timeout="${3:-1200}" log="${4:-}"
deadline=$((SECONDS + timeout))
while (( SECONDS < deadline )); do
  n=$(curl -s -m 3 "localhost:${port}/health" | jq '[.instances[]? | select(.endpoint=="generate")] | length' 2>/dev/null)
  if [[ "${n:-0}" -ge "${want}" ]]; then printf 'ready: %s workers after %ss\n' "${n}" "${SECONDS}"; exit 0; fi
  if [[ -n "${log}" ]] && grep -qE "Traceback|CUDA error|out of memory" "${log}" 2>/dev/null; then
    printf 'startup error:\n'; grep -m5 -E "Error|error" "${log}" | cut -c1-240; exit 1
  fi
  sleep 10
done
printf 'timeout: %s/%s workers\n' "${n:-0}" "${want}"; exit 1
