#!/bin/bash

set -e

# List of DFSP names
DFSPS=(
    "perffsp1" 
    # "perffsp3" 
    # "perffsp5" 
    # "perffsp7"
    )

# Corresponding kubeconfig paths (same order as DFSPS)
KUBECONFIGS=(
  "../kubeconfigs/ml-perf-perffsp1.yaml"
#   "../kubeconfigs/ml-perf-perffsp3.yaml"
#   "../kubeconfigs/ml-perf-perffsp5.yaml"
#   "../kubeconfigs/ml-perf-perffsp7.yaml"
)

# Loop over the array indices
for i in "${!DFSPS[@]}"; do
  dfsp="${DFSPS[$i]}"
  kubeconfig="${KUBECONFIGS[$i]}"
  values_file="../mojaloop-k6-operator/values/values-${dfsp}.yaml"

  echo "Cleaning up old release for $dfsp..."
  helm uninstall "k6-test-${dfsp}" --kubeconfig "$kubeconfig" --namespace mojaloop || true
  
  echo "Deploying K6 test to $dfsp..."

  helm upgrade --install "k6-test-${dfsp}" ../mojaloop-k6-operator \
    -f "$values_file" \
    --kubeconfig "$kubeconfig" \
    --namespace mojaloop &
done

wait
echo "✅ All K6 tests triggered in parallel."
