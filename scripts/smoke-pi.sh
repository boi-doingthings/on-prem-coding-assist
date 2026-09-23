#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PI_DYNAMO_MODEL="${PI_DYNAMO_MODEL:-Qwen/Qwen3-0.6B}" \
"${repo_root}/scripts/pi-local.sh" \
  --no-session \
  --no-extensions \
  --no-skills \
  --no-tools \
  --thinking off \
  --print \
  'Reply with exactly: PI_DYNAMO_OK'
