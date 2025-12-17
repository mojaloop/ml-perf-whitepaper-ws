# Deploy Mojaloop Switch

This step deploys all core Mojaloop switch components (ALS, Quoting Service, ML-API-Adapter, Central-Ledger handlers, Settlement services, etc.) onto the switch Kubernetes cluster.  
Ensure the backend services (Kafka, MySQL, Redis, MongoDB) are fully running before continuing.

DFSP simulator IP addresses used by Mojaloop must be added as hostAliases to key deployments.  
These IPs are obtained from the Terraform-generated ssh_config file created earlier at `ml-perf-whitepaper-ws/infrastructure/provisioning/artifacts/ssh_config`

---
### Set the kubeconfig

```bash
export KUBECONFIG=ml-perf-whitepaper-ws/infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml
```

## Deploy Mojaloop Using TPS-Specific Override Files

Different performance test scenarios require different Mojaloop configurations.  
Override files are stored in:

```
 ml-perf-whitepaper-ws/performance-tests/results/*tps/config-override/mojaloop-values.yaml
```

### Default deployment
```bash
helm -n mojaloop upgrade --install moja mojaloop/mojaloop \
  --version 17.1.0 \
  -f ml-perf-whitepaper-ws/infrastructure/mojaloop/values.yaml
```

### 500 TPS
```bash
helm -n mojaloop upgrade --install moja mojaloop/mojaloop \
  --version 17.1.0 \
  -f ml-perf-whitepaper-ws/infrastructure/mojaloop/values.yaml \
  -f performance-tests/results/500tps/config-override/mojaloop-values.yaml
```

### 1000 TPS
```bash
helm -n mojaloop upgrade --install moja mojaloop/mojaloop \
  --version 17.1.0 \
  -f ml-perf-whitepaper-ws/infrastructure/mojaloop/values.yaml \
  -f performance-tests/results/1000tps/config-override/mojaloop-values.yaml
```

### 2000 TPS
```bash
helm -n mojaloop upgrade --install moja mojaloop/mojaloop \
  --version 17.1.0 \
  -f ml-perf-whitepaper-ws/infrastructure/mojaloop/values.yaml \
  -f performance-tests/results/2000tps/config-override/mojaloop-values.yaml
```

---

## Add HostAliases for DFSP Simulators

Mojaloop services (ALS, Quoting, ML-API-Adapter, TTK Backend) need DNS resolution for DFSP simulator domains:

```
sim-fsp201.local
sim-fsp202.local
...
sim-fsp208.local
```

Retrieve DFSP IPs from the Terraform ssh_config:

```
infrastructure/provisioning/artifacts/ssh_config
```

And update the below file with correct ip addresses
```
ml-perf-whitepaper-ws/infrastructure/mojaloop/hostaliases.json
```

---

## Patch Mojaloop Deployments with HostAliases

### Account Lookup Service
```bash
kubectl patch deployment moja-account-lookup-service \
  -n mojaloop --type='strategic' --patch "$(cat ml-perf-whitepaper-ws/infrastructure/mojaloop/hostaliases.json)"
```

### Quoting Service
```bash
kubectl patch deployment moja-quoting-service-handler \
  -n mojaloop --type='strategic' --patch "$(cat ml-perf-whitepaper-ws/infrastructure/mojaloop/hostaliases.json)"
```

### ML-API-Adapter Notification Handler
```bash
kubectl patch deployment moja-ml-api-adapter-handler-notification \
  -n mojaloop --type='strategic' --patch "$(cat ml-perf-whitepaper-ws/infrastructure/mojaloop/hostaliases.json)"
```

### Testing Toolkit Backend
```bash
kubectl patch statefulset moja-ml-testing-toolkit-backend \
  -n mojaloop --type='strategic' --patch "$(cat ml-perf-whitepaper-ws/infrastructure/mojaloop/hostaliases.json)"
```

---

## Patch Mojaloop Deployments with performance test specific configmaps

Different performance test scenarios require different Mojaloop configmap overrides.
Override files are stored in:

```
 ml-perf-whitepaper-ws/performance-tests/results/*tps/configmaps
```
e.g. For 1000 TPS apply below batch

### 1000 TPS
#### Account lookup service
```
kubectl patch configmap moja-account-lookup-service-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat ml-perf-whitepaper-ws/performance-tests/results/1000tps/configmaps/account-lookup-service-config.json)" '{data: {"default.json": $cfg}}')"
```

#### Quoting service
```
kubectl patch configmap moja-quoting-service-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat  ml-perf-whitepaper-ws/performance-tests/results/1000tps/configmaps/quoting-service-config.json)" '{data: {"default.json": $cfg}}')"
```

#### Quoting service handler
```
kubectl patch configmap moja-quoting-service-handler-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat  ml-perf-whitepaper-ws/performance-tests/results/1000tps/configmaps/quoting-service-handler-config.json)" '{data: {"default.json": $cfg}}')"
```

#### ml-api-adapter
```
kubectl patch configmap moja-ml-api-adapter-service-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat  ml-perf-whitepaper-ws/performance-tests/results/1000tps/configmaps/ml-api-adapter-service-config.json)" '{data: {"default.json": $cfg}}')"
```

#### ml-api-adapter-notification handler
```
kubectl patch configmap moja-ml-api-adapter-handler-notification-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat  ml-perf-whitepaper-ws/performance-tests/results/1000tps/configmaps/ml-api-adapter-handler-notification-config.json)" '{data: {"default.json": $cfg}}')"
```

#### Prepare handler 
```
kubectl patch configmap moja-centralledger-handler-transfer-prepare-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat  ml-perf-whitepaper-ws/performance-tests/results/1000tps/configmaps/centralledger-handler-transfer-prepare-config.json)" '{data: {"default.json": $cfg}}')"
```

#### Position batch handler
```
kubectl patch configmap moja-handler-pos-batch-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat  ml-perf-whitepaper-ws/performance-tests/results/1000tps/configmaps/handler-pos-batch-config.json)" '{data: {"default.json": $cfg}}')"
```

#### Fulfil handler
```
kubectl patch configmap moja-centralledger-handler-transfer-fulfil-config -n mojaloop \
  --type merge \
  -p "$(jq -n --arg cfg "$(cat  ml-perf-whitepaper-ws/performance-tests/results/1000tps/configmaps/centralledger-handler-transfer-fulfil-config.json)" '{data: {"default.json": $cfg}}')"
```

#### Restart services after config change
```
    for d in \
      moja-account-lookup-service \
      moja-centralledger-handler-transfer-fulfil \
      moja-centralledger-handler-transfer-prepare \
      moja-handler-pos-batch \
      moja-ml-api-adapter-handler-notification \
      moja-ml-api-adapter-service \
      moja-quoting-service \
      moja-quoting-service-handler; do

      replicas=$(kubectl get deploy $d -n mojaloop -o jsonpath='{.spec.replicas}')
      echo "Scaling $d to 0..."
      kubectl scale deploy/$d -n mojaloop --replicas=0
      echo "Scaling $d back to $replicas..."
      kubectl scale deploy/$d -n mojaloop --replicas=$replicas
    done
```

## Mojaloop Switch Deployment is Complete

Once:

- all Helm releases are deployed  
- all pods in the mojaloop namespace are Ready  
- hostAliases are applied  

…the Mojaloop switch is ready to receive traffic from DFSP simulators and k6 load tests.
