#!/usr/bin/env bash
# Render a coding-harness config for the campus endpoint and install it.
#
#   CAMPUS_LLM_URL=https://llm.example.edu/v1 CAMPUS_LLM_MODEL=Qwen/Qwen3.5-122B-A10B \
#     ./scripts/setup-harness.sh opencode          # writes ~/.config/opencode/opencode.json
#   ./scripts/setup-harness.sh --print codex        # print instead of writing
#
# The API key is never written to disk: harnesses read it from CAMPUS_LLM_KEY
# (or OPENAI_API_KEY for aider). Existing configs are backed up with a timestamp.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
templates="${repo_root}/config/harnesses"
print_only=0
if [[ "${1:-}" == "--print" ]]; then print_only=1; shift; fi
harness="${1:-}"

base_url="${CAMPUS_LLM_URL:-http://127.0.0.1:8000/v1}"
model="${CAMPUS_LLM_MODEL:-Qwen/Qwen3.5-122B-A10B}"
context="${CAMPUS_LLM_CONTEXT:-131072}"
max_output="${CAMPUS_LLM_MAX_OUTPUT:-16384}"

case "${harness}" in
  opencode) src=opencode.json;            dest="${HOME}/.config/opencode/opencode.json" ;;
  aider)    src=aider.conf.yml;           dest="${HOME}/.aider.conf.yml" ;;
  aider-metadata) src=aider.model.metadata.json; dest="${HOME}/.aider.model.metadata.json" ;;
  codex)    src=codex-config.toml;        dest="${HOME}/.codex/config.toml" ;;
  qwen)     src=qwen-code-settings.json;  dest="${HOME}/.qwen/settings.json" ;;
  pi)       src=pi-models.json;           dest="${HOME}/.pi/agent/models.json" ;;
  goose)    src=goose-campus.json;        dest="${HOME}/.config/goose/custom_providers/campus.json" ;;
  crush)    src=crushrc;                  dest="${HOME}/.config/crush/crushrc" ;;
  zed)      src=zed-settings.json;        dest="" ;;  # merge by hand into Zed settings
  mini-swe-agent) src=mini-swe-agent.yaml; dest="" ;;
  *)
    printf 'usage: %s [--print] {opencode|aider|aider-metadata|codex|qwen|pi|goose|crush|zed|mini-swe-agent}\n' "$0" >&2
    exit 2
    ;;
esac

rendered="$(sed -e "s#@@BASE_URL@@#${base_url}#g" -e "s#@@MODEL@@#${model}#g" \
  -e "s#@@CONTEXT@@#${context}#g" -e "s#@@MAX_OUTPUT@@#${max_output}#g" "${templates}/${src}")"

if (( print_only )) || [[ -z "${dest}" ]]; then
  printf '%s\n' "${rendered}"
  [[ -z "${dest}" ]] && printf '\n# (%s: merge the above into your own config)\n' "${harness}" >&2
  exit 0
fi

mkdir -p "$(dirname "${dest}")"
if [[ -f "${dest}" ]]; then
  cp "${dest}" "${dest}.bak.$(date +%Y%m%d%H%M%S)"
fi
printf '%s\n' "${rendered}" >"${dest}"
printf 'Wrote %s (model %s at %s)\n' "${dest}" "${model}" "${base_url}"
printf 'Set your key: export CAMPUS_LLM_KEY=<key from the campus gateway>\n'
printf 'Disable telemetry: source %s/telemetry-off.sh\n' "${templates}"
