#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"

exec pi \
  --provider dynamo-local \
  --model "${PI_DYNAMO_MODEL:-Qwen/Qwen3.5-122B-A10B}" \
  "$@"
