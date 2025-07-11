#!/bin/bash

set -e

# List of DFSP names
DFSPS=(
    # "pm012-dfsp-100" 
    "pm012-dfsp-300" 
    # "pm012-dfsp-500" 
    # "pm012-dfsp-700"
    )

# Corresponding kubeconfig paths (same order as DFSPS)
KUBECONFIGS=(
#   "../kubeconfigs/ml-perf-pm012-dfsp-100.yaml"
  "../kubeconfigs/ml-perf-pm012-dfsp-300.yaml"
#   "../kubeconfigs/ml-perf-pm012-dfsp-500.yaml"
#   "../kubeconfigs/ml-perf-pm012-dfsp-700.yaml"
)

# Loop over the array indices
for i in "${!DFSPS[@]}"; do
  dfsp="${DFSPS[$i]}"
  kubeconfig="${KUBECONFIGS[$i]}"
  values_file="../mojaloop-k6-operator/values/values-${dfsp}.yaml"

  echo "Cleaning up old release for $dfsp..."
  helm uninstall "k6-test-${dfsp}" --kubeconfig "$kubeconfig" --namespace ${dfsp} || true
  
  echo "Deploying K6 test to $dfsp..."

  helm upgrade --install "k6-test-${dfsp}" ../mojaloop-k6-operator \
    -f "$values_file" \
    --kubeconfig "$kubeconfig" \
    --namespace ${dfsp} &
done

wait
echo "✅ All K6 tests triggered in parallel."
