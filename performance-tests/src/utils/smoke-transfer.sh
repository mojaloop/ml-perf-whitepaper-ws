#!/usr/bin/env bash
# smoke-transfer.sh — end-to-end validator for a single DFSP ↔ Switch transfer.
#
# Runs the 3-step SDK outbound flow through the curl-k6-test pod in the k6 cluster:
#   1) POST /sim/${SRC_FSP}/outbound/transfers                  → WAITING_FOR_PARTY_ACCEPTANCE
#   2) PUT  /sim/${SRC_FSP}/outbound/transfers/{id} acceptParty → WAITING_FOR_QUOTE_ACCEPTANCE
#   3) PUT  /sim/${SRC_FSP}/outbound/transfers/{id} acceptQuote → COMPLETED
#
# Exits 0 only if step 3 reaches COMPLETED. On any unexpected state or HTTP
# error, prints the offending response body and exits non-zero.
#
# Usage:
#   SCENARIO=500tps ./smoke-transfer.sh
#
#   # overrides:
#   SRC_FSP=fsp201 DEST_FSP=fsp203 DEST_MSISDN=37039811929 ./smoke-transfer.sh
#
# Requires:
#   - HTTPS_PROXY pointing at the bastion SOCKS5 tunnel
#   - The k6 cluster's kubeconfig to exist
#   - curl-k6-test pod deployed in the k6-test namespace
#     (kubectl apply -f performance-tests/src/utils/curl-pod.yaml)
#   - k6 cluster CoreDNS patched to resolve sim-fspNNN.local (applied via
#     infrastructure/k6-infrastructure/apply-coredns-hosts.bash)

set -euo pipefail

# ---- parameters (overridable via env) --------------------------------------
SCENARIO="${SCENARIO:-base}"
NAMESPACE="${NAMESPACE:-k6-test}"
POD="${POD:-curl-k6-test}"
SRC_FSP="${SRC_FSP:-fsp201}"
DEST_FSP="${DEST_FSP:-fsp202}"
SRC_MSISDN="${SRC_MSISDN:-17039811918}"
DEST_MSISDN="${DEST_MSISDN:-17039811929}"
AMOUNT="${AMOUNT:-1}"
CURRENCY="${CURRENCY:-XXX}"
CURL_TIMEOUT="${CURL_TIMEOUT:-60}"

# ---- kubeconfig resolution --------------------------------------------------
# Honor caller's KUBECONFIG if set, otherwise fall back to the scenario default.
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
ARTIFACTS="${ROOT_DIR}/performance-tests/results/${SCENARIO}/artifacts"
export KUBECONFIG="${KUBECONFIG:-${ARTIFACTS}/kubeconfigs/kubeconfig-k6.yaml}"
[[ -f "${KUBECONFIG}" ]] || { echo "ERROR: KUBECONFIG=${KUBECONFIG} does not exist" >&2; exit 1; }

# ---- tool prereqs -----------------------------------------------------------
command -v kubectl >/dev/null || { echo "ERROR: kubectl not found in PATH" >&2; exit 1; }
command -v jq      >/dev/null || { echo "ERROR: jq not found in PATH"      >&2; exit 1; }

# ---- pod prereq -------------------------------------------------------------
if ! kubectl -n "${NAMESPACE}" get pod "${POD}" >/dev/null 2>&1; then
  echo "ERROR: pod ${NAMESPACE}/${POD} not found." >&2
  echo "Deploy with: kubectl apply -f performance-tests/src/utils/curl-pod.yaml" >&2
  exit 1
fi
POD_PHASE="$(kubectl -n "${NAMESPACE}" get pod "${POD}" -o jsonpath='{.status.phase}')"
[[ "${POD_PHASE}" == "Running" ]] \
  || { echo "ERROR: pod ${NAMESPACE}/${POD} is in phase ${POD_PHASE}, expected Running" >&2; exit 1; }

# ---- derived --------------------------------------------------------------
BASE_URL="http://sim-${SRC_FSP}.local/sim/${SRC_FSP}/outbound/transfers"
UUID="$(uuidgen 2>/dev/null || echo "test-$(date +%s)-$$")"

printf '=== smoke-transfer ===\n'
printf '  scenario      : %s\n' "${SCENARIO}"
printf '  route         : %s -> %s\n' "${SRC_FSP}" "${DEST_FSP}"
printf '  MSISDN        : %s -> %s\n' "${SRC_MSISDN}" "${DEST_MSISDN}"
printf '  amount        : %s %s\n' "${AMOUNT}" "${CURRENCY}"
printf '  homeTxId      : %s\n' "${UUID}"
printf '  endpoint base : %s\n' "${BASE_URL}"
printf '\n'

# ---- helpers --------------------------------------------------------------
# Assert JSON body's .currentState == expected; otherwise dump body, exit 1.
check_state() {
  local body="$1" expected="$2" step="$3"
  local state
  state="$(echo "${body}" | jq -r '.currentState // "<missing>"' 2>/dev/null || echo "<non-json>")"
  if [[ "${state}" != "${expected}" ]]; then
    echo "FAIL [${step}] expected currentState=${expected}, got ${state}" >&2
    echo "---response body---" >&2
    echo "${body}" | jq . 2>/dev/null >&2 || echo "${body}" >&2
    exit 1
  fi
  printf '  OK   [%s] currentState=%s\n' "${step}" "${state}"
}

# ---- Step 1: POST /transfers ------------------------------------------------
printf '[1/3] POST  %s\n' "${BASE_URL}"
RESP1="$(kubectl -n "${NAMESPACE}" exec -i "${POD}" -- \
  curl -sS --max-time "${CURL_TIMEOUT}" -X POST "${BASE_URL}" \
    -H 'content-type: application/json' --data-binary @- <<JSON
{
  "from": { "displayName": "smoke", "idType": "MSISDN", "idValue": "${SRC_MSISDN}" },
  "to":   { "idType": "MSISDN", "idValue": "${DEST_MSISDN}" },
  "amountType": "SEND",
  "currency": "${CURRENCY}",
  "amount": "${AMOUNT}",
  "transactionType": "TRANSFER",
  "note": "smoke-transfer",
  "homeTransactionId": "${UUID}"
}
JSON
)"
check_state "${RESP1}" "WAITING_FOR_PARTY_ACCEPTANCE" "1/3 POST"

TRANSFER_ID="$(echo "${RESP1}" | jq -r '.transferId // empty')"
[[ -n "${TRANSFER_ID}" ]] \
  || { echo "FAIL: no transferId in POST response" >&2; echo "${RESP1}" | jq . >&2; exit 1; }
printf '        transferId=%s\n\n' "${TRANSFER_ID}"

# ---- Step 2: PUT acceptParty ------------------------------------------------
printf '[2/3] PUT   %s/%s  {acceptParty:true}\n' "${BASE_URL}" "${TRANSFER_ID}"
RESP2="$(kubectl -n "${NAMESPACE}" exec -i "${POD}" -- \
  curl -sS --max-time "${CURL_TIMEOUT}" -X PUT "${BASE_URL}/${TRANSFER_ID}" \
    -H 'content-type: application/json' --data-binary @- <<'JSON'
{ "acceptParty": true }
JSON
)"
check_state "${RESP2}" "WAITING_FOR_QUOTE_ACCEPTANCE" "2/3 acceptParty"
printf '\n'

# ---- Step 3: PUT acceptQuote ------------------------------------------------
printf '[3/3] PUT   %s/%s  {acceptQuote:true}\n' "${BASE_URL}" "${TRANSFER_ID}"
RESP3="$(kubectl -n "${NAMESPACE}" exec -i "${POD}" -- \
  curl -sS --max-time "${CURL_TIMEOUT}" -X PUT "${BASE_URL}/${TRANSFER_ID}" \
    -H 'content-type: application/json' --data-binary @- <<'JSON'
{ "acceptQuote": true }
JSON
)"
check_state "${RESP3}" "COMPLETED" "3/3 acceptQuote"
printf '\n'

printf 'PASS  smoke-transfer COMPLETED   transferId=%s\n' "${TRANSFER_ID}"
