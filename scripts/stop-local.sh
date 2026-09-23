#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"

enroot_pid_file="${repo_root}/.state/enroot-disagg.pid"
if [[ -s "${enroot_pid_file}" ]]; then
  enroot_pid="$(<"${enroot_pid_file}")"
  if kill -0 "${enroot_pid}" 2>/dev/null; then
    kill -TERM -- "-${enroot_pid}" 2>/dev/null || kill -TERM "${enroot_pid}"
    for _ in {1..30}; do
      kill -0 "${enroot_pid}" 2>/dev/null || break
      sleep 1
    done
  fi
  rm -f "${enroot_pid_file}"
fi

for container in dynamo-qwen35-agg dynamo-qwen35-disagg dynamo-qwen3-smoke; do
  if docker container inspect "${container}" >/dev/null 2>&1; then
    docker stop --timeout 30 "${container}"
    docker rm "${container}"
  fi
done

docker compose -f "${repo_root}/deploy/local/compose.yaml" down
printf 'Stopped local services; retained persistent model cache at %s.\n' \
  "${DYNAMO_MODEL_CACHE:-${repo_root}/.state/model-cache}"
