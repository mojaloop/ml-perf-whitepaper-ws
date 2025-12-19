# Deploy DFSP Simulators

Each DFSP runs its own dedicated MicroK8s cluster and deploys a Mojaloop Simulator consisting of:

- Backend  
- Scheme Adapter  
- Cache  
- (Optional) Additional replicas for performance scenarios  

DFSPs act as payers or payees depending on the performance test flow.  
DFSPs communicate with the Mojaloop switch using local DNS mappings that point simulator traffic to core switch services.

---

## Deployment Instructions

A **single generic script** is used to deploy all DFSP simulators:

```
ml-perf-whitepaper-ws/infrastructure/dfsp/deploy.bash
```

Inside the script, update the following two variables:

---

### 1. SWITCH_IP

The IP address of one of the node that runs Mojaloop switch services:

- `account-lookup-service.local`
- `quoting-service.local`
- `ml-api-adapter.local`

This IP is available in the Terraform-generated file: `sw1-n1`

```
ml-perf-whitepaper-ws/infrastructure/provisioning/artifacts/ssh_config
```

---

### 2. REPLICAS

The number of `sdk-scheme-adapter` replicas to deploy per DFSP.

Recommended values:

| Test Scenario | sdk-scheme-adapter Replicas |
|---------------|-----------------------------|
| Default / < 500 TPS | 4–8 |
| 1000 TPS | 12 |
| 1000 TPS (Kafka + MySQL replication) | 12 |
| 2000 TPS | 12 |

Set this inside `deploy.bash`:

```bash
SWITCH_IP=10.x.x.x
REPLICAS=12
```

---

## Run Deployment

```
./ml-perf-whitepaper-ws/infrastructure/dfsp/deploy.bash
```

For each DFSP (`fsp201`–`fsp208`), the script:

1. Loads the correct kubeconfig  
2. Creates the `dfsps` namespace  
3. Adds Docker Hub imagePullSecrets  
4. Installs the Mojaloop Simulator Helm chart  
5. Patches hostAliases so DFSPs resolve:  
   - `account-lookup-service.local`  
   - `quoting-service.local`  
   - `ml-api-adapter.local`  
6. Extends liveness & readiness probes  
7. Scales out scheme-adapter replicas  
8. Updates CoreDNS host mappings  
9. Restarts CoreDNS  


---

## Provisioning DFSP Simulators

After deployment, DFSP simulators must be provisioned in the Mojaloop Switch using TTK:

- Participants  
- Endpoints  
- Callback URLs  
- ILP Secrets  
- ALS registration

### Access the TTK UI locally

Add below in your `/etc/hosts`
```
# for perf testing ttk ui
127.0.0.1      prometheus.local grafana.local ml-api-adapter.local central-ledger.local account-lookup-service.local account-lookup-service-admin.local quoting-service.local central-settlement-service.local transaction-request-service.local central-settlement.local bulk-api-adapter.local moja-simulator.local sim-payerfsp.local sim-payeefsp.local sim-testfsp1.local sim-testfsp2.local sim-testfsp3.local sim-testfsp4.local mojaloop-simulators.local finance-portal.local operator-settlement.local settlement-management.local testing-toolkit.local testing-toolkit-specapi.local
```
Port forward the ingress controller of mojaloop switch 

```bash
kubectl port-forward -n ingress daemonset/nginx-ingress-microk8s-controller 80:80 443:443 --address 0.0.0.0
```
Open the TTK UI in browser: 
http://testing-toolkit.local/admin/outbound_request

### Load and run the On-boarding collection and env file

Load the below collection and env file in the TTK UI and run it.

The TTK collection for on-boarding of dfsps for performance testing is at:
```
ml-perf-whitepaper-ws/infrastructure/dfsp/collections/hub
```
The corresponding env file is at:
```
ml-perf-whitepaper-ws/infrastructure/dfsp/collections/perf-env-example.json
```

---

## Summary

- One generic DFSP deployment script (`deploy.bash`)  
- User configures only:  
  - `SWITCH_IP`  
  - `REPLICAS`  
- All DFSP clusters get consistent DNS, replicas, and setup 
- Onboard the DFSPs 
