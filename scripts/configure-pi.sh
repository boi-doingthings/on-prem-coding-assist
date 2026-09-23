#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pi_config_dir="${PI_CONFIG_DIR:-/home/yagupta/.pi/agent}"

install -m 0600 "${repo_root}/config/pi-models.json" "${pi_config_dir}/models.json"
printf 'Installed Dynamo provider config at %s/models.json\n' "${pi_config_dir}"

