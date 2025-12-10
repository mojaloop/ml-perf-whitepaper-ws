#!/bin/bash
export HTTPS_PROXY=socks5://127.0.0.1:1080

for i in {201..208} 
do
  echo "Starting deployment of FSP${i}..."
  echo ${i}

  SWITCH_IP=10.112.2.205 # 

  export KUBECONFIG=~/Workspace/mojaloop/perf/ml-perf-whitepaper-ws/phases/02-infrastructure/artifacts/kubeconfigs/kubeconfig-fsp${i}.yaml
  # echo $KUBECONFIG
  
  # helm -n dfsps upgrade --install moja mojaloop/mojaloop --version 17.1.0 --values=ml-perf-whitepaper-ws/phases/08-dfsp/values-fsp201.yaml
  helm -n dfsps upgrade --install dfsp mojaloop/mojaloop-simulator --version 15.10.0 --values=ml-perf-whitepaper-ws/phases/08-dfsp/values-fsp${i}.yaml --create-namespace

  kubectl patch deployment dfsp-sim-fsp${i}-scheme-adapter -n dfsps \
    --type='json' \
    -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/hostAliases\",\"value\":[{\"ip\":\"${SWITCH_IP}\",\"hostnames\":[\"account-lookup-service.local\",\"quoting-service.local\",\"ml-api-adapter.local\"]}]}]"

  kubectl scale deployment dfsp-sim-fsp${i}-scheme-adapter -n dfsps --replicas=16

  echo "End deployment of FSP${i}"
  echo "-------------------------------"
  echo ""
done

