#!/bin/bash
for i in {1..8} 
do
  echo "Starting deployment of FSP${i}..."
  echo ${i}

  export KUBECONFIG=~/Workspace/mojaloop/perf/ml-perf-whitepaper-ws/phases/02-infrastructure/artifacts/kubeconfigs/kubeconfig-fsp10${i}.yaml
  echo $KUBECONFIG
  
  kubectl create ns dfsps

  # helm -n dfsps upgrade --install moja mojaloop/mojaloop --version 17.1.0 --values=ml-perf-whitepaper-ws/phases/08-dfsp/values-fsp201.yaml
  helm -n dfsps upgrade --install dfsp mojaloop/mojaloop-simulator --version 15.10.0 --values=ml-perf-whitepaper-ws/phases/08-dfsp/values-fsp20${i}.yaml

  echo "End deployment of FSP${i}"
  echo "-------------------------------"
  echo ""
done

