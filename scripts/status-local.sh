#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"

docker compose -f "${repo_root}/deploy/local/compose.yaml" ps
docker ps --filter name=dynamo-qwen --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'

enroot_pid_file="${repo_root}/.state/enroot-disagg.pid"
if [[ -s "${enroot_pid_file}" ]]; then
  enroot_pid="$(<"${enroot_pid_file}")"
  if kill -0 "${enroot_pid}" 2>/dev/null; then
    ps -p "${enroot_pid}" -o pid,etime,stat,args
  else
    printf 'Stale Enroot PID file: %s\n' "${enroot_pid_file}" >&2
  fi
fi

curl --silent --show-error --fail --max-time 10 http://127.0.0.1:8000/health
