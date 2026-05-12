#!/usr/bin/env bash
# Full Mojaloop deploy sequence for perf testing.
#
# All multi-replica deployments are patched with:
#   - strategy: Recreate  (kills all helm-install pods at once so the topology
#                          scheduler starts from zero, not a skewed baseline)
#   - topologySpreadConstraints:
#       hostname  DoNotSchedule + nodeTaintsPolicy:Honor
#                 Honor excludes tainted infra nodes (kafka, mysql) from the
#                 domain count. Without it those nodes count as domains with 0
#                 pods, making skew = max-0 = 2 after the 4th pod → Pending.
#                 With Honor: only the 4 switch nodes are eligible domains →
#                 DoNotSchedule enforces strict 2-per-node distribution.
#       zone      ScheduleAnyway (best-effort zone spread)
#
# Some deployments also get hostAliases for FSP simulator name resolution.
#
# Usage (run from the directory that contains ml-perf-whitepaper-ws/):
#   ./ml-perf-whitepaper-ws/infrastructure/mojaloop/deploy.sh

set -euo pipefail

WS="./ml-perf-whitepaper-ws"
NS="mojaloop"
CMAPS="$WS/performance-tests/results-round2/500tps/configmaps"
HOSTALIASES="$WS/infrastructure/mojaloop/hostaliases.json"

HA=$(jq -c '.spec.template.spec.hostAliases' "$HOSTALIASES")

# ─── 1. Helm install ─────────────────────────────────────────────────────────
echo "==> [1/3] Helm upgrade/install mojaloop 17.1.0 ..."
helm -n "$NS" upgrade --install moja mojaloop/mojaloop \
  --version 17.1.0 \
  -f "$WS/infrastructure/mojaloop/values-v17.1.0.yaml" \
  -f "$WS/performance-tests/results-round2/500tps/config-override/mojaloop-values.yaml"

# ─── 2. Patch configmaps ─────────────────────────────────────────────────────
# No rollout triggered here — changes are picked up by the rollouts in step 3.
echo ""
echo "==> [2/3] Patching configmaps ..."

patch_cm() {
  local cm="$1" file="$2"
  echo "  configmap: $cm"
  kubectl patch configmap "$cm" -n "$NS" --type merge \
    -p "$(jq -n --arg v "$(cat "$file")" '{data: {"default.json": $v}}')"
}

patch_cm moja-account-lookup-service-config                 "$CMAPS/account-lookup-service-config.json"
patch_cm moja-quoting-service-config                        "$CMAPS/quoting-service-config.json"
patch_cm moja-quoting-service-handler-config                "$CMAPS/quoting-service-handler-config.json"
patch_cm moja-ml-api-adapter-service-config                 "$CMAPS/ml-api-adapter-service-config.json"
patch_cm moja-ml-api-adapter-handler-notification-config    "$CMAPS/ml-api-adapter-handler-notification-config.json"
patch_cm moja-centralledger-handler-transfer-prepare-config "$CMAPS/centralledger-handler-transfer-prepare-config.json"
patch_cm moja-handler-pos-batch-config                      "$CMAPS/handler-pos-batch-config.json"
patch_cm moja-centralledger-handler-transfer-fulfil-config  "$CMAPS/centralledger-handler-transfer-fulfil-config.json"

# ─── 3. Deployment patches ───────────────────────────────────────────────────
# Each deployment gets exactly one patch (one rollout).
# Recreate + topology in the same patch means:
#   1. All helm-install pods die at once (no skewed baseline)
#   2. New pods schedule from zero against DoNotSchedule → even distribution
echo ""
echo "==> [3/3] Patching deployments (Recreate + topology [+ hostAliases]) ..."

# Soft anti-affinity patch for single-replica deployments.
# Tells the scheduler to prefer nodes with fewer moja-instance pods, spreading
# singletons across switch nodes instead of piling them all on sw1-n1.
# $1 = deployment name (skipped if deployment does not exist)
_patch_single() {
  local deploy="$1"
  if ! kubectl get deployment "$deploy" -n "$NS" &>/dev/null; then
    echo "  deployment/$deploy (not found, skipping)"
    return 0
  fi
  echo "  deployment/$deploy (singleton spread)"
  kubectl patch deployment "$deploy" -n "$NS" --type=merge -p '{
    "spec": {
      "template": {
        "spec": {
          "affinity": {
            "podAntiAffinity": {
              "preferredDuringSchedulingIgnoredDuringExecution": [
                {
                  "weight": 100,
                  "podAffinityTerm": {
                    "topologyKey": "kubernetes.io/hostname",
                    "labelSelector": {
                      "matchExpressions": [
                        {
                          "key": "app.kubernetes.io/instance",
                          "operator": "In",
                          "values": ["moja"]
                        }
                      ]
                    }
                  }
                }
              ]
            }
          }
        }
      }
    }
  }'
}

# Build topology patch for a given app.kubernetes.io/name label.
# $1 = app name, $2 = optional hostAliases JSON array (omit for no hostAliases)
_patch() {
  local deploy="$1" app="$2" ha="${3:-}"
  echo "  deployment/$deploy"
  local spec
  if [[ -n "$ha" ]]; then
    spec=$(jq -n --arg a "$app" --argjson ha "$ha" '{
      "hostAliases": $ha,
      "topologySpreadConstraints": [
        {"maxSkew":1,"topologyKey":"kubernetes.io/hostname",
         "whenUnsatisfiable":"DoNotSchedule",
         "nodeAffinityPolicy":"Honor",
         "nodeTaintsPolicy":"Honor",
         "labelSelector":{"matchLabels":{"app.kubernetes.io/name":$a}}},
        {"maxSkew":1,"topologyKey":"topology.kubernetes.io/zone",
         "whenUnsatisfiable":"ScheduleAnyway",
         "labelSelector":{"matchLabels":{"app.kubernetes.io/name":$a}}}
      ]
    }')
  else
    spec=$(jq -n --arg a "$app" '{
      "topologySpreadConstraints": [
        {"maxSkew":1,"topologyKey":"kubernetes.io/hostname",
         "whenUnsatisfiable":"DoNotSchedule",
         "nodeAffinityPolicy":"Honor",
         "nodeTaintsPolicy":"Honor",
         "labelSelector":{"matchLabels":{"app.kubernetes.io/name":$a}}},
        {"maxSkew":1,"topologyKey":"topology.kubernetes.io/zone",
         "whenUnsatisfiable":"ScheduleAnyway",
         "labelSelector":{"matchLabels":{"app.kubernetes.io/name":$a}}}
      ]
    }')
  fi
  kubectl patch deployment "$deploy" -n "$NS" --type=merge -p "$(
    jq -n --argjson s "$spec" \
      '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null},"template":{"spec":$s}}}'
  )"
}

# Deployments that also need hostAliases for FSP simulator resolution:
_patch moja-account-lookup-service              account-lookup-service              "$HA"
_patch moja-ml-api-adapter-handler-notification ml-api-adapter-handler-notification "$HA"
_patch moja-quoting-service-handler             quoting-service-handler             "$HA"

# Remaining multi-replica deployments (topology + Recreate, no hostAliases):
_patch moja-als-msisdn-oracle                       als-msisdn-oracle
_patch moja-centralledger-handler-transfer-fulfil   centralledger-handler-transfer-fulfil
_patch moja-centralledger-handler-transfer-prepare  centralledger-handler-transfer-prepare
_patch moja-centralledger-service                   centralledger-service
_patch moja-handler-pos-batch                       handler-pos-batch
_patch moja-ml-api-adapter-service                  ml-api-adapter-service
_patch moja-quoting-service                         quoting-service

# Single-replica deployments: soft anti-affinity to spread across switch nodes.
# These have no topology spread constraints (1 pod = no spread possible), but
# anti-affinity against moja-instance pods biases the scheduler away from
# whichever switch node is already most loaded with mojaloop pods.
#
# Central settlement singletons are the main offenders: at 500 TPS they process
# committed transfers through Kafka and consume real CPU. All three must be spread.
_patch_single moja-centralsettlement-handler-deferredsettlement
_patch_single moja-centralsettlement-handler-rules
_patch_single moja-centralsettlement-service
# Admin/utility singletons — low-traffic but still consume node resources:
_patch_single moja-account-lookup-service-admin
_patch_single moja-centralledger-handler-admin-transfer
_patch_single moja-centralledger-handler-transfer-get
_patch_single moja-transaction-requests-service
_patch_single moja-ml-testing-toolkit-frontend
_patch_single moja-bulk-api-adapter

# TTK backend statefulset: hostAliases only (single replica, no topology needed).
echo "  statefulset/moja-ml-testing-toolkit-backend"
kubectl patch statefulset moja-ml-testing-toolkit-backend -n "$NS" --type=strategic \
  --patch "$(cat "$HOSTALIASES")"

# ─── Wait for rollouts ────────────────────────────────────────────────────────
echo ""
echo "==> Waiting for rollouts to complete ..."
for d in \
  moja-account-lookup-service \
  moja-als-msisdn-oracle \
  moja-centralledger-handler-transfer-fulfil \
  moja-centralledger-handler-transfer-prepare \
  moja-centralledger-service \
  moja-handler-pos-batch \
  moja-ml-api-adapter-handler-notification \
  moja-ml-api-adapter-service \
  moja-quoting-service \
  moja-quoting-service-handler; do
  echo "  rollout: $d"
  kubectl rollout status deployment -n "$NS" "$d" --timeout=600s
done

echo ""
echo "Deploy complete."
