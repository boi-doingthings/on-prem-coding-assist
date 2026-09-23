#!/usr/bin/env bash
set -euo pipefail

base_url="${DYNAMO_BASE_URL:-http://127.0.0.1:8000}"
model="${DYNAMO_SERVED_MODEL:-Qwen/Qwen3.5-122B-A10B}"
timeout_seconds="${DYNAMO_SMOKE_TIMEOUT_SECONDS:-180}"
run_tool_call="${DYNAMO_SMOKE_TOOL_CALL:-1}"

printf 'Health:\n'
curl --silent --show-error --fail --max-time "${timeout_seconds}" \
  "${base_url}/health" | python3 -m json.tool

printf '\nText completion:\n'
curl --silent --show-error --fail --max-time "${timeout_seconds}" \
  "${base_url}/v1/chat/completions" \
  --header 'Content-Type: application/json' \
  --data "{
    \"model\": \"${model}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Reply with exactly: DYNAMO_OK\"}],
    \"temperature\": 0,
    \"max_tokens\": 32
  }" | python3 -m json.tool

if [[ "${run_tool_call}" != "1" ]]; then
  exit 0
fi

printf '\nTool-call completion:\n'
curl --silent --show-error --fail --max-time "${timeout_seconds}" \
  "${base_url}/v1/chat/completions" \
  --header 'Content-Type: application/json' \
  --data "{
    \"model\": \"${model}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"What is the weather in Seattle? Use the tool.\"}],
    \"tools\": [{
      \"type\": \"function\",
      \"function\": {
        \"name\": \"get_weather\",
        \"description\": \"Get current weather for a city\",
        \"parameters\": {
          \"type\": \"object\",
          \"properties\": {\"city\": {\"type\": \"string\"}},
          \"required\": [\"city\"]
        }
      }
    }],
    \"tool_choice\": \"auto\",
    \"temperature\": 0,
    \"max_tokens\": 256
  }" | python3 -m json.tool
