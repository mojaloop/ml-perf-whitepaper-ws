# Mojaloop k6 Performance Tests

This directory contains the k6 load-testing implementation used to perform end-to-end performance testing of a Mojaloop switch.  
Tests are executed using the **k6 Operator** and deployed as Kubernetes resources via a Helm chart.

The k6 cluster generates load and sends traffic to DFSP simulators, which in turn interact with the Mojaloop switch.

---

## Overview

The k6 tests simulate the full Mojaloop transaction lifecycle:

1. **Discovery (ALS Party Lookup)**
2. **Quote**
3. **Transfer**

Each virtual user executes the full flow and records detailed metrics for:

- End-to-end latency
- Per-phase latency
- Success/failure rates
- Achieved TPS

Traffic distribution across DFSPs is configurable using weighted FSP pairs.

---

## Directory Structure

```
mojaloop-k6-operator/
├── Chart.yaml                # Helm chart definition
├── values.yaml               # Default Helm values
├── scripts/
│   ├── tests.js              # Main k6 test implementation
│   └── trigger-tests.sh      # Entry point to trigger tests
├── templates/
│   ├── configmap.yaml        # Injects tests.js into k6 runner
│   └── testrun.yaml          # k6 TestRun custom resource
├── values/
│   └── values.yaml           # Test-scenario-specific overrides
├── utils/                    # Helper scripts (optional)
└── README.md
```

---

## Test Flow (tests.js)

Each test iteration executes the following phases:

### 1. Discovery Phase

- Calls `GET /parties/MSISDN/{msisdn}`
- Measures `discovery_time`
- Fails fast on non-200 responses

### 2. Quote Phase

- Calls `POST /quotes`
- Measures `quote_time`
- Uses randomly generated transaction and quote IDs

### 3. Transfer Phase

- Calls `POST /simpleTransfers`
- Uses ILP packet and condition from quote response
- Measures `transfer_time`
- Records end-to-end latency (`e2e_time`)

All phases propagate a `traceparent` header for distributed tracing.

---

## Configuration (values/values.yaml)

Test behavior is fully driven by Helm values.

### Key Parameters

```yaml
k6:
  targetTxnCount: 500000     # Total transactions to execute
  targetTps: 2000            # Target transactions per second
  abortOnError: false
  transferAmount: "1"
  currency: "XXX"
```

### DFSP Traffic Distribution

Weighted FSP pairs control traffic routing:

```yaml
fspPairs:
  - source: fsp201
    dest: fsp202
    weight: 0.25
  - source: fsp203
    dest: fsp204
    weight: 0.25
  - source: fsp205
    dest: fsp206
    weight: 0.25
  - source: fsp207
    dest: fsp208
    weight: 0.25
```

### DFSP Configuration

```yaml
fspConfig: |
  {
    "fsp201": {
      "id": "fsp201",
      "msisdn": "17039811918",
      "baseUrl": "http://sim-fsp201.local/sim/fsp201/outbound",
      "startMsisdn": "17039811918",
      "endMsisdn": "17039811918"
    }
  }
```

---

## Pre-test Setup

Before running k6 load tests, a few preparatory steps are required to ensure sufficient MSISDN data is available across DFSP simulators and the Mojaloop switch. Each DFSP should have **at least 1000 MSISDNs** provisioned to avoid contention during high‑TPS tests.

---

### 1. Create a curl utility pod (k6 cluster)

A curl pod is used as a utility workspace to run MSISDN registration scripts against DFSP simulators.

```bash
kubectl --kubeconfig ../../../infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-k6.yaml \
  apply -n k6-test -f curl-pod.yaml
```

Shell into the pod:

```bash
kubectl --kubeconfig ../../../infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-k6.yaml \
  exec -n k6-test -it curl -- sh
```

Copy the registration script into the pod and execute it:

```bash
kubectl --kubeconfig ../../../infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-k6.yaml \
  cp register-msisdnOracle-on-sim.sh k6-test/curl:/tmp/register-msisdnOracle-on-sim.sh

kubectl --kubeconfig ../../../infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-k6.yaml \
  exec -n k6-test -it curl -- sh -c "chmod +x /tmp/register-msisdnOracle-on-sim.sh && /tmp/register-msisdnOracle-on-sim.sh"
```

This registers MSISDNs on each DFSP simulator.

---

### 2. Insert MSISDNs into `oracle_msisdn` database (Mojaloop switch)

After registering MSISDNs on the simulators, the same MSISDNs must be inserted into the `oracle_msisdn` database used by the Mojaloop switch.

Shell into the MySQL pod on the Mojaloop switch cluster:

```bash
kubectl --kubeconfig ../../../infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml -n mojaloop exec -it mysqldb-0 -- bash
```

Copy and execute the insertion script:

```bash
kubectl --kubeconfig ../../../infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml -n mojaloop cp insert-msisdnOracle.sh mysqldb-0:/tmp/insert-msisdnOracle.sh
kubectl --kubeconfig ../../../infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml -n mojaloop exec -it mysqldb-0 -- bash -c "chmod +x /tmp/insert-msisdnOracle.sh && /tmp/insert-msisdnOracle.sh"
```

---

### 3. (Optional) Kafka monitoring using Redpanda Console UI

For Kafka monitoring during test execution, a lightweight Redpanda Console UI can be deployed in the `mojaloop` namespace.

```bash
kubectl apply --kubeconfig ../../../infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml -n mojaloop -f kafka-debug-ui-pod.yaml
```

Port-forward locally:

```bash
kubectl port-forward -n mojaloop kafka-debug-ui 3077:8080
```

Access the UI from a browser:

```
http://localhost:3077/
```

---

## Test Execution

### Entry Point

All tests are triggered using a single script:

```bash
scripts/trigger-tests.sh
```

### What the Script Does

1. Uses the k6 cluster kubeconfig
2. Uninstalls any previous test run
3. Deploys the Helm chart
4. Creates a new `TestRun` CR
5. k6 Operator starts the test automatically

### Run the Test

```bash
cd scripts
./trigger-tests.sh
```

---

## Kubernetes Resources

- **ConfigMap**: Injects `tests.js` into the k6 runner
- **TestRun CR**: Controls execution via k6 Operator
- **Parallelism**: Configurable via Helm values
- **Resources**: CPU/memory limits configurable per test scenario

---

## Test Results & Summary

At test completion, k6 prints:

- Standard k6 summary
- Custom JSON summary including:
  - Target vs achieved TPS
  - Success rate
  - p95 latencies
  - PASS / FAIL status

Example summary:

```json
{
  "status": "PASSED",
  "actual_tps": 1987,
  "success_rate": 99.2,
  "e2e_time_p95": 8200
}
```

---

## Notes & Best Practices

- Ensure **CoreDNS is configured** so `sim-fsp*.local` domains resolve in the k6 cluster
- Ensure DFSP simulators and Mojaloop switch are fully healthy before running tests
- Increase `preAllocatedVUs` and resource limits for higher TPS tests
- For large-scale tests, consider using a fixed `TARGET_TXN_COUNT` strategy if derived calculations become inaccurate

---

## Summary

- Automated k6 load testing using k6 Operator
- End-to-end Mojaloop transaction simulation (Discovery → Quote → Transfer)
- Configurable TPS, transaction counts, and DFSP traffic mix
- Metrics and thresholds built-in
- Single command test execution
