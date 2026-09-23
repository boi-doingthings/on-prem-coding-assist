#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"

docker info --format 'docker_root={{.DockerRootDir}} runtimes={{json .Runtimes}}'
docker run --rm --gpus all nvcr.io/nvidia/cuda:13.0.1-base-ubuntu24.04 \
  nvidia-smi --query-gpu=index,name,uuid,memory.total,driver_version --format=csv,noheader
kubectl version --client
helm version --short

