#!/bin/bash
export HTTPS_PROXY=socks5://127.0.0.1:1080

for i in {201..208}
do
  echo "Starting deployment of FSP${i}..."
  echo ${i}

  SWITCH_IP=10.112.2.250

  export KUBECONFIG=~/.kube/kubeconfig-fsp${i}.yaml
  
  kubectl create ns dfsps

  kubectl create secret docker-registry dockerhub-secret \
    --docker-server="https://index.docker.io/v1/" \
    --docker-username="${DOCKERHUB_USERNAME}" \
    --docker-password="${DOCKERHUB_TOKEN}" \
    --docker-email="${DOCKERHUB_EMAIL}" \
    -n dfsps

kubectl patch serviceaccount default \
    -n dfsps \
    -p '{"imagePullSecrets": [{"name": "dockerhub-secret"}]}'

  # Install / upgrade the DFSP simulator
  helm -n dfsps upgrade --install dfsp mojaloop/mojaloop-simulator \
    --version 15.10.0 \
    --values=ml-perf-whitepaper-ws/phases/08-dfsp/values-fsp${i}.yaml \
    --create-namespace

  # Patch hostAliases so scheme-adapter can reach switch services
  kubectl patch deployment dfsp-sim-fsp${i}-scheme-adapter -n dfsps \
    --type='json' \
    -p="[
      {
        \"op\":\"add\",
        \"path\":\"/spec/template/spec/hostAliases\",
        \"value\":[
          {
            \"ip\":\"${SWITCH_IP}\",
            \"hostnames\":[
              \"account-lookup-service.local\",
              \"quoting-service.local\",
              \"ml-api-adapter.local\"
            ]
          }
        ]
      }
    ]"

  # Patch liveness + readiness probe to periodSeconds = 180
  kubectl patch deployment dfsp-sim-fsp${i}-scheme-adapter -n dfsps \
    --type='json' \
    -p="[
      {
        \"op\":\"replace\",
        \"path\":\"/spec/template/spec/containers/0/livenessProbe/periodSeconds\",
        \"value\":180
      },
      {
        \"op\":\"replace\",
        \"path\":\"/spec/template/spec/containers/0/readinessProbe/periodSeconds\",
        \"value\":180
      }
    ]"

  # Now scale out to 12 replicas (all with updated probes + hostAliases)
  # kubectl scale deployment dfsp-sim-fsp${i}-scheme-adapter -n dfsps --replicas=0
  kubectl scale deployment dfsp-sim-fsp${i}-scheme-adapter -n dfsps --replicas=12
  # kubectl scale deployment dfsp-sim-fsp${i}-backend -n dfsps --replicas=0
  # kubectl scale deployment dfsp-sim-fsp${i}-backend -n dfsps --replicas=1
  # kubectl scale deployment dfsp-sim-fsp${i}-cache -n dfsps --replicas=0
  # kubectl scale deployment dfsp-sim-fsp${i}-cache -n dfsps --replicas=1

  # patch the coredn
kubectl -n kube-system patch configmap coredns \
  --type merge \
  -p "$(cat << EOF
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
        hosts {
          ${SWITCH_IP} account-lookup-service.local quoting-service.local ml-api-adapter.local
          fallthrough
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
EOF
)"

  # restart coredns
  kubectl -n kube-system rollout restart deployment coredns
  echo "End deployment of FSP${i}"
  echo "-------------------------------"
  echo ""
done
