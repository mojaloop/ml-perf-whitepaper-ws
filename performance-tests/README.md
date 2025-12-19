# Performance Tests

This directory contains all **k6-based performance tests** used to benchmark the Mojaloop switch under realistic, high-throughput conditions.

The tests are executed using the **k6 Operator** on a dedicated Kubernetes cluster and simulate full Mojaloop transaction flows across multiple DFSPs, including **Discovery → Quotes → Transfers**.

---

## Directory Structure

```text
performance-tests/
├── src/
│   ├── README.md
│   │   - Detailed documentation for k6 tests
│   │   - Test flow, configuration, and execution
│   │
│   ├── mojaloop-k6-operator/
│   │   - Helm chart for running k6 tests via k6 Operator
│   │   - k6 test script (Discovery, Quotes, Transfers)
│   │
│   ├── scripts/
│   │   - Helper scripts to trigger test runs
│   │
│   ├── values/
│   │   - Scenario-specific values.yaml files
│   │   - TPS, transaction count, DFSP pairing configuration
│   │
│   └── utils/
│       - Utility scripts for pre-test setup
│       - MSISDN provisioning, Kafka UI, curl pod, etc.
│
└── results/
│   - Test results and summaries
│   - Scenario-specific configuration overrides
│   - TPS-based tuning references (e.g. 500 / 1000 / 2000 TPS)
```

---

## Test Model

- **Load Generator**: k6 Operator (Kubernetes-native)
- **Execution Model**: Constant Arrival Rate (target TPS)
- **Transaction Flow**:
  1. Party Discovery (ALS)
  2. Quote request
  3. Transfer execution
- **DFSP Topology**:
  - Multiple DFSP simulators acting as **payers** and **payees**
  - Weighted DFSP pairing supported
- **Metrics Captured**:
  - End-to-end latency
  - Phase-wise latency (Discovery / Quotes / Transfers)
  - Success rate
  - Completed transactions
  - TPS achieved

---

## Typical Workflow

1. **Prepare Infrastructure**  
   Ensure Mojaloop switch, DFSPs, and k6 infrastructure are running.  
   See: [`ml-perf-whitepaper-ws/infrastructure/README.md`](../infrastructure/README.md)

2. **Test Execution**
   Execute the performance tests.  
   See: [`ml-perf-whitepaper-ws/performance-tests/src/README.md`](src/README.md)

3. **Collect Results**  
   Review and record summaries, logs, and metrics under `ml-perf-whitepaper-ws/performance-tests/results`.

---
 
## Test Results

The k6 test suite captures **end-to-end, phase-level, and system-level metrics** to provide a complete performance profile of the Mojaloop switch under load.

---

### Transaction-level Metrics

These metrics describe the functional success and throughput of the test:

- **`completed_transactions`**  
  Total number of successful end-to-end transfers completed.

- **`success_rate`**  
  Ratio of successful transactions to total attempted transactions.

- **Actual TPS**  
  Effective transactions per second achieved, calculated as:
  ```
  completed_transactions / test_duration
  ```

- **Dropped iterations**  
  Number of iterations dropped when the system cannot keep up with the configured arrival rate.

---

### End-to-End Latency Metrics

Measured from the start of discovery until transfer completion:

- **`e2e_time`**
  - Average
  - Median
  - p90 / p95
  - Max  

Represents full Mojaloop transaction latency.

---

### Phase-wise Latency Metrics

Latency is broken down by Mojaloop transaction phases to isolate bottlenecks:

1. **`discovery_time`**
   - ALS party lookup latency

2. **`quote_time`**
   - Time to process quote request

3. **`transfer_time`**
   - Time to process transfer request

Each phase reports:
- Average
- Median
- p90 / p95
- Max

---

### HTTP & Network Metrics

Collected automatically by k6 to analyze network and request behavior:

- **`http_req_duration`**
- **`http_req_waiting`**
- **`http_req_connecting`**
- **`http_req_sending`**
- **`http_req_receiving`**
- **`http_req_failed`**
- **`http_reqs`** (total HTTP requests sent)

These metrics help distinguish **application latency** from **network or connection-level issues**.

---

### Virtual User (VU) Metrics

Used to understand concurrency and backpressure:

- **`vus`**
  - Active virtual users during the test

- **`vus_max`**
  - Maximum VUs allocated to sustain the target TPS

High `vus_max` values typically indicate increased system latency or contention.

---

### Failure Metrics

- **`failed_transactions`**
  - Count of failed transactions across all phases

- **Phase-specific check failures**
  - Discovery failures (ALS)
  - Quote failures
  - Transfer failures

These are surfaced via k6 checks and logged with trace identifiers for debugging.

---

### Test Summary Output

At the end of each test run, k6 prints a **structured summary** including:

- Target vs achieved TPS
- Completed transactions
- Success rate
- p95 end-to-end latency
- Test pass/fail status (based on thresholds)

This summary is used as the canonical result in `results/<scenario>/README.md`.


---

## Notes

- Test parameters are fully driven via Helm values and environment variables.
- Multiple TPS scenarios (e.g. 500 / 1000 / 2000 TPS) can be executed using different values files.
- The k6 cluster is isolated from the Mojaloop switch and DFSP clusters to ensure clean load generation.

---

This structure allows repeatable, scalable, and production-like performance testing of Mojaloop.
