# Test Results

The k6 test suite captures **end-to-end, phase-level, and system-level metrics** to provide a complete performance profile of the Mojaloop switch under load.

---

## Getting Test Result
Once you trigger the tests you can monitor the k6 pods created in `k6-test` namespace on k6 node.  
```bash
kubectl --kubeconfig ../../infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-k6.yaml \
  get pods -n k6-test
```
Check the pod logs and get the execution results


## Transaction-level Metrics

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

## End-to-End Latency Metrics

Measured from the start of discovery until transfer completion:

- **`e2e_time`**
  - Average
  - Median
  - p90 / p95
  - Max  

Represents full Mojaloop transaction latency.

---

## Phase-wise Latency Metrics

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

## HTTP & Network Metrics

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

## Virtual User (VU) Metrics

Used to understand concurrency and backpressure:

- **`vus`**
  - Active virtual users during the test

- **`vus_max`**
  - Maximum VUs allocated to sustain the target TPS

High `vus_max` values typically indicate increased system latency or contention.

---

## Failure Metrics

- **`failed_transactions`**
  - Count of failed transactions across all phases

- **Phase-specific check failures**
  - Discovery failures (ALS)
  - Quote failures
  - Transfer failures

These are surfaced via k6 checks and logged with trace identifiers for debugging.

---

## Test Summary Output

At the end of each test run, k6 prints a **structured summary** including:

- Target vs achieved TPS
- Completed transactions
- Success rate
- p95 end-to-end latency
- Test pass/fail status (based on thresholds)

This summary is used as the canonical result in `results/<scenario>/README.md`.


