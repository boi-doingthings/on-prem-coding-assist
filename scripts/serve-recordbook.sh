#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${RECORDBOOK_PORT:-8080}"

printf 'Recordbook: http://127.0.0.1:%s/recordbook/\n' "${port}"
printf 'Remote access: ssh -L %s:127.0.0.1:%s %s\n' \
  "${port}" "${port}" "$(hostname -s)"
exec python3 -m http.server "${port}" --bind 127.0.0.1 --directory "${repo_root}"
