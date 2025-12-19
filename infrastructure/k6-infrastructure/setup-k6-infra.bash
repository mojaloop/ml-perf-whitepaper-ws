#!/usr/bin/env bash
set -euo pipefail
export HTTPS_PROXY=socks5://127.0.0.1:1080
# -----------------------------------------------------------------------------
# k6 infrastructure bootstrap for Mojaloop performance testing
#
# What this script does:
#  1) Sets KUBECONFIG to the dedicated k6 cluster kubeconfig
#  2) Creates the "k6-test" namespace (idempotent)
#  3) Creates/updates a Docker Hub imagePullSecret in "k6-test" (idempotent)
#  4) Patches the default ServiceAccount in "k6-test" to use the imagePullSecret
#  5) Installs/Upgrades the k6-operator using Helm into the "k6-operator" namespace
#  6) Patches CoreDNS to resolve DFSP simulator domains (sim-fsp201.local ... sim-fsp208.local)
#  7) Restarts CoreDNS
# -----------------------------------------------------------------------------

K6_NAMESPACE="k6-test"
K6_OPERATOR_NAMESPACE="k6-operator"
KUBECONFIG="ml-perf-whitepaper-ws/infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-k6.yaml"
SSH_CONFIG_PATH="ml-perf-whitepaper-ws/infrastructure/provisioning/artifacts/ssh-config"

echo "Using KUBECONFIG     : ${KUBECONFIG}"
echo "Using namespace      : ${K6_NAMESPACE}"
echo "Using operator namespace      : ${K6_OPERATOR_NAMESPACE}"
echo "Using SSH config path: ${SSH_CONFIG_PATH}"

# Basic checks
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH"; exit 1; }
command -v helm   >/dev/null 2>&1 || { echo "ERROR: helm not found in PATH"; exit 1; }
command -v awk    >/dev/null 2>&1 || { echo "ERROR: awk not found in PATH"; exit 1; }
command -v sed    >/dev/null 2>&1 || { echo "ERROR: sed not found in PATH"; exit 1; }

# Ensure we can talk to the cluster
kubectl version --client >/dev/null
kubectl get nodes >/dev/null

# Create namespace (idempotent)
kubectl get namespace "${K6_NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${K6_NAMESPACE}"

# Validate required env vars for Docker Hub secret
: "${DOCKERHUB_USERNAME:?ERROR: DOCKERHUB_USERNAME is not set}"
: "${DOCKERHUB_TOKEN:?ERROR: DOCKERHUB_TOKEN is not set}"
: "${DOCKERHUB_EMAIL:?ERROR: DOCKERHUB_EMAIL is not set}"

# Create/update docker registry secret (idempotent apply)
# kubectl -n "${K6_NAMESPACE}" create secret docker-registry dockerhub-secret \
#   --docker-server="https://index.docker.io/v1/" \
#   --docker-username="${DOCKERHUB_USERNAME}" \
#   --docker-password="${DOCKERHUB_TOKEN}" \
#   --docker-email="${DOCKERHUB_EMAIL}" \
#   --dry-run=client -o yaml | kubectl apply -f -

# # Patch default serviceaccount to use the pull secret
# kubectl -n "${K6_NAMESPACE}" patch serviceaccount default \
#   -p '{"imagePullSecrets":[{"name":"dockerhub-secret"}]}' >/dev/null

# # Install/upgrade k6 operator
# echo "Installing k6-operator"
# helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
# helm repo update >/dev/null

# helm upgrade --install k6-operator grafana/k6-operator \
#   --namespace "${K6_OPERATOR_NAMESPACE}" \
#   --create-namespace

# -----------------------------------------------------------------------------
# CoreDNS patching for DFSP simulator domains
# -----------------------------------------------------------------------------

# Build hosts mapping (prefer parsing Terraform-generated ssh_config)
build_dfsp_hosts_block() {
  if [[ ! -f "${SSH_CONFIG_PATH}" ]]; then
    echo "ERROR: SSH config not found at '${SSH_CONFIG_PATH}'."
    echo "Provide SSH_CONFIG_PATH=<path> or DFSP_HOSTS='<ip sim-fsp201.local\n...>'"
    return 1
  fi

  local out=""
  local ip=""
  for i in {201..208}; do
    ip="$(awk -v host="fsp${i}" '
      $1=="Host" && $2==host {inhost=1; next}
      inhost && $1=="HostName" {print $2; exit}
      inhost && $1=="Host" {exit}
    ' "${SSH_CONFIG_PATH}")"

    if [[ -z "${ip}" ]]; then
      echo "ERROR: Could not find HostName for Host fsp${i} in ${SSH_CONFIG_PATH}"
      return 1
    fi
    out="${out}  ${ip} sim-fsp${i}.local\n"
  done

  printf "%b" "${out}"
}

DFSP_HOST_LINES="$(build_dfsp_hosts_block)"

echo ""
echo "DFSP simulator host mappings to apply in CoreDNS:"
echo "------------------------------------------------"
echo "${DFSP_HOST_LINES}"
echo "------------------------------------------------"
echo ""

# Fetch current CoreDNS Corefile
CURRENT_COREFILE="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"

echo "current coredns file"
echo "------------------------------------------------"
echo "${CURRENT_COREFILE}"
echo "------------------------------------------------"


# If already configured, skip
if echo "${CURRENT_COREFILE}" | grep -q "sim-fsp201\.local"; then
  echo "CoreDNS already contains sim-fsp*.local entries. Skipping CoreDNS patch."
else
  # Optional: remove the leading "  " from DFSP_HOST_LINES for prettier indentation in CoreDNS
  DFSP_HOST_LINES_CLEAN="$(printf "%s" "${DFSP_HOST_LINES}" | sed 's/^[[:space:]]\{2\}//')"

  # Create a temp file for the hosts block
  HOSTS_BLOCK_FILE="$(mktemp -t coredns-hosts.XXXXXX)"
  COREFILE_FILE="$(mktemp -t coredns-corefile.XXXXXX)"
  UPDATED_FILE="$(mktemp -t coredns-updated.XXXXXX)"

  # Ensure cleanup even if script exits early
  trap 'rm -f "${HOSTS_BLOCK_FILE}" "${COREFILE_FILE}" "${UPDATED_FILE}"' EXIT

  # Write the hosts block with correct Corefile indentation:
  # - 4 spaces before "hosts"
  # - 6 spaces before each host line and "fallthrough"
  cat > "${HOSTS_BLOCK_FILE}" <<EOF
    # DFSP simulator hosts (added by setup-k6-infra.bash)
    hosts {
$(printf "%s\n" "${DFSP_HOST_LINES_CLEAN}" | sed 's/^/      /')
      fallthrough
    }
EOF

  # Save current Corefile to a file for awk to process
  printf "%s\n" "${CURRENT_COREFILE}" > "${COREFILE_FILE}"

  # Insert hosts block before 'prometheus' if present, else before final '}'
  awk -v blockfile="${HOSTS_BLOCK_FILE}" '
    function print_block() {
      while ((getline line < blockfile) > 0) print line
      close(blockfile)
    }
    BEGIN { inserted=0 }
    /^[[:space:]]*prometheus[[:space:]]/ && inserted==0 {
      print_block()
      inserted=1
    }
    /^}[[:space:]]*$/ && inserted==0 {
      print_block()
      inserted=1
    }
    { print }
  ' "${COREFILE_FILE}" > "${UPDATED_FILE}"

  UPDATED_COREFILE="$(cat "${UPDATED_FILE}")"

  # Build YAML merge patch safely
  PATCH_PAYLOAD="$(
    cat <<EOF
data:
  Corefile: |
$(printf "%s\n" "${UPDATED_COREFILE}" | sed 's/^/    /')
EOF
  )"

  echo "updated coredns file"
  echo "------------------------------------------------"
  echo "${UPDATED_COREFILE}"
  echo "------------------------------------------------"

  # Patch the configmap (merge) with the updated Corefile
  kubectl -n kube-system patch configmap coredns --type merge --patch "${PATCH_PAYLOAD}"

  echo "Restarting CoreDNS..."
  kubectl -n kube-system rollout restart deployment coredns
  kubectl -n kube-system rollout status deployment coredns
fi

echo ""
echo "Done."
echo "k6-operator installed in namespace '${K6_OPERATOR_NAMESPACE}'. CoreDNS configured for DFSP simulator domains."
