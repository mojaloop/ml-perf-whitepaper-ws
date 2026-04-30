#!/usr/bin/env bash
# Apply the k6 cluster's CoreDNS ConfigMap with the DFSP + switch hosts block
# spliced in. Idempotent (kubectl apply).
#
# Usage:
#   SCENARIO=500tps ./apply-coredns-hosts.bash
#
# Requires:
#   - HTTPS_PROXY pointing at the bastion SOCKS5 tunnel
#   - The scenario's kubeconfig-k6.yaml to exist
#   - The scenario's artifacts/k6-coredns-hosts.conf to exist (run `make k8s-hostaliases` first)
set -euo pipefail

SCENARIO="${SCENARIO:-base}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACTS="${ROOT_DIR}/performance-tests/results/${SCENARIO}/artifacts"

# Honor caller's KUBECONFIG if already set (e.g. from the guide); otherwise
# fall back to the scenario's k6 kubeconfig so the script stays runnable standalone.
export KUBECONFIG="${KUBECONFIG:-${ARTIFACTS}/kubeconfigs/kubeconfig-k6.yaml}"

HOSTS_CONF="${ARTIFACTS}/k6-coredns-hosts.conf"
[[ -f "${HOSTS_CONF}" ]] || {
  echo "ERROR: ${HOSTS_CONF} not found. Run: make k8s-hostaliases SCENARIO=${SCENARIO}" >&2
  exit 1
}
HOSTS_BLOCK="$(cat "${HOSTS_CONF}")"

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
  labels:
    addonmanager.kubernetes.io/mode: EnsureExists
    k8s-app: kube-dns
data:
  Corefile: |
    .:53 {
        errors
        health {
          lameduck 5s
        }
        ready
        log . {
          class error
        }
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }
${HOSTS_BLOCK}
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
EOF

echo "CoreDNS ConfigMap applied. CoreDNS will auto-reload via the 'reload' directive within ~30s."
echo "Force immediate rollout with:"
echo "  kubectl -n kube-system rollout restart deployment coredns"
