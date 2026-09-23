#!/usr/bin/env bash
set -euo pipefail

dynamo_lab_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Keep local credentials/configuration out of Git while making every wrapper
# consume the same environment. The explicit workspace .env takes precedence.
if [[ -f "${dynamo_lab_root}/.env" ]]; then
  while IFS='=' read -r env_name env_value; do
    [[ -z "${env_name}" || "${env_name}" == \#* ]] && continue
    export "${env_name}=${env_value}"
  done < "${dynamo_lab_root}/.env"
fi

# Explicit safety switch for public-model operations after a credential has
# been rotated or when a caller wants to guarantee anonymous Hub access.
if [[ "${DYNAMO_HF_ANONYMOUS:-0}" == "1" ]]; then
  unset HF_TOKEN HUGGING_FACE_HUB_TOKEN
fi

export PATH="${dynamo_lab_root}/bin:/cm/shared/apps/rootless-docker/bin:${PATH}"
export DOCKER_HOST="unix:///raid/docker/tmp/xdg_runtime_dir_1004/docker.sock"
export XDG_RUNTIME_DIR="/raid/docker/tmp/xdg_runtime_dir_1004"
export MINIKUBE_HOME="${dynamo_lab_root}/.state/minikube"
export KUBECONFIG="${dynamo_lab_root}/.state/kubeconfig"
