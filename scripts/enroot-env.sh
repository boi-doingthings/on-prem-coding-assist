#!/usr/bin/env bash

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export ENROOT_CACHE_PATH="${DYNAMO_ENROOT_CACHE_PATH:-${repo_root}/.state/enroot/cache}"
export ENROOT_DATA_PATH="${DYNAMO_ENROOT_DATA_PATH:-/tmp/enroot-data-$(id -u)}"
export ENROOT_RUNTIME_PATH="${DYNAMO_ENROOT_RUNTIME_PATH:-/tmp/enroot-runtime-$(id -u)}"
export ENROOT_CONFIG_PATH="${DYNAMO_ENROOT_CONFIG_PATH:-${repo_root}/.state/enroot/config}"

mkdir -p \
  "${ENROOT_CACHE_PATH}" \
  "${ENROOT_DATA_PATH}" \
  "${ENROOT_RUNTIME_PATH}" \
  "${ENROOT_CONFIG_PATH}"
