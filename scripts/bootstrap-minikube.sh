#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${repo_root}/scripts/env.sh"

profile="${MINIKUBE_PROFILE:-dynamo-lab}"
memory="${MINIKUBE_MEMORY_MB:-524288}"
# The managed execution session currently exposes two CPUs to the rootless
# Docker daemon. Override this after launching the daemon from a wider cpuset.
cpus="${MINIKUBE_CPUS:-2}"

minikube start \
  --profile "${profile}" \
  --driver docker \
  --container-runtime docker \
  --gpus all \
  --memory "${memory}" \
  --cpus "${cpus}" \
  --kubernetes-version v1.34.3

minikube --profile "${profile}" update-context
kubectl get nodes -o wide
