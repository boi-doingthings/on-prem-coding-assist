#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DYNAMO_CONTAINER_NAME=dynamo-qwen3-smoke \
DYNAMO_MODEL=Qwen/Qwen3-0.6B \
DYNAMO_SERVED_MODEL=Qwen/Qwen3-0.6B \
DYNAMO_ENABLE_MULTIMODAL=0 \
DYNAMO_QWEN35_NVFP4=0 \
DYNAMO_AGG_GPUS="${DYNAMO_CANARY_GPU:-0}" \
  "${repo_root}/scripts/start-local-agg.sh"
