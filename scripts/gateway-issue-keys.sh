#!/usr/bin/env bash
# Issue LiteLLM virtual keys for a course roster.
#
#   GATEWAY_URL=https://llm.example.edu LITELLM_MASTER_KEY=... \
#     ./scripts/gateway-issue-keys.sh roster.csv CS4803-fall26
#
# roster.csv: one "user_id,email" per line (no header). Writes
# keys-<course>.csv (user_id,email,key) with mode 600 for secure distribution
# through the LMS; keys are not printed to the terminal.
#
# Defaults suit an IDE/agent course; override per course:
#   KEY_RPM=30  KEY_TPM=400000  KEY_PARALLEL=2  KEY_DURATION=120d  KEY_MODELS=campus-coder
set -euo pipefail

roster="${1:?usage: $0 roster.csv course-id}"
course="${2:?usage: $0 roster.csv course-id}"
gateway="${GATEWAY_URL:?set GATEWAY_URL}"
: "${LITELLM_MASTER_KEY:?set LITELLM_MASTER_KEY}"
out="keys-${course}.csv"

umask 077
: >"${out}"
while IFS=, read -r user email; do
  [[ -z "${user}" ]] && continue
  body="$(jq -n --arg u "${user}" --arg e "${email}" --arg c "${course}" \
    --argjson rpm "${KEY_RPM:-30}" --argjson tpm "${KEY_TPM:-400000}" \
    --argjson par "${KEY_PARALLEL:-2}" --arg dur "${KEY_DURATION:-120d}" \
    --arg models "${KEY_MODELS:-campus-coder}" \
    '{user_id: $u, key_alias: ($c + ":" + $u), duration: $dur,
      models: ($models | split(",")), rpm_limit: $rpm, tpm_limit: $tpm,
      max_parallel_requests: $par,
      metadata: {course: $c, email: $e, trace_consent: false}}')"
  key="$(curl --silent --show-error --fail "${gateway}/key/generate" \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    -H 'Content-Type: application/json' -d "${body}" | jq -r .key)"
  printf '%s,%s,%s\n' "${user}" "${email}" "${key}" >>"${out}"
done <"${roster}"
printf 'Issued %s keys for %s -> %s (mode 600)\n' "$(wc -l <"${out}")" "${course}" "${out}"
