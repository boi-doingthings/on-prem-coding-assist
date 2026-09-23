#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"
# shellcheck source=enroot-env.sh
source "${repo_root}/scripts/enroot-env.sh"

runtime_image="${DYNAMO_RUNTIME_IMAGE:-nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.3.0}"
enroot_tag="${DYNAMO_ENROOT_DOCKER_TAG:-dynamo-vllm-enroot:1.3.0}"
output="${DYNAMO_ENROOT_IMAGE:-${repo_root}/.state/enroot/images/dynamo-vllm-1.3.0.sqsh}"
seed="dynamo-enroot-seed-$$"

mkdir -p "$(dirname "${output}")"
if [[ -f "${output}" ]]; then
  printf 'Enroot image already exists: %s\n' "${output}"
  exit 0
fi

if ! docker image inspect "${enroot_tag}" >/dev/null 2>&1; then
  trap 'docker rm -f "${seed}" >/dev/null 2>&1 || true' EXIT
  docker create --name "${seed}" "${runtime_image}" /bin/true >/dev/null
  docker commit --change 'CMD ["/bin/true"]' "${seed}" "${enroot_tag}" >/dev/null
  docker rm "${seed}" >/dev/null
  trap - EXIT
fi

enroot import --output "${output}" "dockerd://${enroot_tag}"
printf 'Created reusable Enroot image: %s\n' "${output}"
