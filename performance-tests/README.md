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
   See: [`ml-perf-whitepaper-ws/performance-tests/results/README.md`](results/README.md)

---
 
## Notes

- Test parameters are fully driven via Helm values and environment variables.
- Multiple TPS scenarios (e.g. 500 / 1000 / 2000 TPS) can be executed using different values files.
- The k6 cluster is isolated from the Mojaloop switch and DFSP clusters to ensure clean load generation.

---

This structure allows repeatable, scalable, and production-like performance testing of Mojaloop.
