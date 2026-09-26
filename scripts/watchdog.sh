#!/usr/bin/env bash
# Data-plane watchdog for a Dynamo endpoint.
#
# /health can report healthy while the engine no longer returns tokens (seen
# in this lab above the concurrency cliff). This probe sends a real 1-token
# completion; after WATCHDOG_FAILURES consecutive failures it runs
# WATCHDOG_ACTION (e.g. requeue the Slurm serving job) and resets.
#
#   WATCHDOG_MODEL=Qwen/Qwen3.5-122B-A10B \
#   WATCHDOG_ACTION='scontrol requeue $SERVE_JOB_ID' ./scripts/watchdog.sh
set -uo pipefail

url="${WATCHDOG_URL:-http://127.0.0.1:8000}"
model="${WATCHDOG_MODEL:?set WATCHDOG_MODEL to the served model name}"
interval="${WATCHDOG_INTERVAL_SECONDS:-60}"
timeout="${WATCHDOG_TIMEOUT_SECONDS:-30}"
threshold="${WATCHDOG_FAILURES:-2}"
action="${WATCHDOG_ACTION:-}"
failures=0

body="$(jq -n --arg m "${model}" \
  '{model: $m, messages: [{role: "user", content: "ping"}], max_tokens: 1, temperature: 0}')"
while true; do
  started=$(date +%s.%N)
  if curl --silent --fail --max-time "${timeout}" "${url}/v1/chat/completions" \
       -H 'Content-Type: application/json' -d "${body}" | jq -e '.choices | length > 0' >/dev/null; then
    printf '%s ok %.2fs\n' "$(date -u +%FT%TZ)" "$(echo "$(date +%s.%N) - ${started}" | bc)"
    failures=0
  else
    failures=$((failures + 1))
    printf '%s FAIL (%s/%s)\n' "$(date -u +%FT%TZ)" "${failures}" "${threshold}"
    if (( failures >= threshold )); then
      if [[ -n "${action}" ]]; then
        printf '%s running action: %s\n' "$(date -u +%FT%TZ)" "${action}"
        bash -c "${action}" || printf 'action failed\n'
      fi
      failures=0
    fi
  fi
  sleep "${interval}"
done
