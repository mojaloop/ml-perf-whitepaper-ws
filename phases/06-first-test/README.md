# Phase 06: First Test Run

> **Purpose**: Validate the entire setup with a small-scale test
> 
> **Time Required**: 30 minutes
> 
> **Outcome**: Confirmation that all components work together before full-scale testing

## 🎯 Why This Phase Matters

Before running expensive, hours-long performance tests, we need to verify:
- ✓ K6 can reach Mojaloop endpoints
- ✓ Authentication and security work
- ✓ Transactions complete successfully
- ✓ Metrics are being collected
- ✓ No configuration issues

## 📋 Pre-test Checklist

```bash
# Run automated pre-flight check
./preflight-check.sh

# Expected output:
Pre-flight Check
================
INFRASTRUCTURE:
✅ Mojaloop cluster: 15 nodes ready
✅ K6 cluster: 8 nodes ready
✅ VPC peering: Active

SERVICES:
✅ Mojaloop API: Responding
✅ All 8 DFSPs: Healthy
✅ K6 operator: Running

CONNECTIVITY:
✅ K6 → Mojaloop: Connected
✅ Average latency: 0.8ms
✅ Security groups: Configured

MONITORING:
✅ Prometheus (Mojaloop): Collecting metrics
✅ Prometheus (K6): Configured
✅ Grafana dashboards: Loaded

🎉 Ready for first test!
```

## 🚀 Run First Test

### Test 1: Single Transaction

```bash
# Run a single transaction to verify end-to-end flow
./run-single-transaction.sh

# Output:
Single Transaction Test
======================
From: perffsp-1 (MSISDN: 19012345001)
To: perffsp-5 (MSISDN: 19012345401)
Amount: 100 USD

[→] Starting transaction...
[✓] Party lookup: 24ms
[✓] Quote request: 31ms
[✓] Transfer: 45ms
[✓] Total time: 100ms

Transaction ID: 550e8400-e29b-41d4-a716-446655440001
Status: COMPLETED
```

### Test 2: Small Load Test (10 TPS for 1 minute)

```bash
# Run small load test
./run-first-load-test.sh

# Or manually:
kubectl apply -f tests/first-test-10tps.yaml

# Monitor progress
watch kubectl logs k6-first-test-10tps
```

Expected results:
```
execution: local
    script: mojaloop-p2p-transfers.js
    output: -

scenarios: (100.00%) 1 scenario, 10 max VUs, 1m30s max duration
         ✓ p2p_transfers: 10 iterations/s for 1m0s

running (1m00.2s), 00/10 VUs, 600 complete iterations

✓ party lookup successful
✓ quote created successfully  
✓ transfer completed

checks.........................: 100.00% ✓ 1800    ✗ 0
data_received..................: 318 kB  5.3 kB/s
data_sent......................: 636 kB  11 kB/s
http_req_duration..............: avg=42.3ms p(95)=68.2ms
http_req_waiting...............: avg=41.8ms p(95)=67.5ms
http_reqs......................: 1800    29.99/s
iteration_duration.............: avg=98.7ms p(95)=124.3ms
iterations.....................: 600     10/s
vus............................: 10      min=10    max=10
vus_max........................: 10      min=10    max=10
```

## 📊 Verify Metrics Collection

### Check Prometheus

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:80

# Open browser to http://localhost:9090
# Run query: rate(http_requests_total[1m])
```

### Check Grafana Dashboards

```bash
# Get Grafana credentials
./get-grafana-creds.sh

# Port-forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80

# Open browser to http://localhost:3000
# Navigate to: Dashboards → Mojaloop → Performance Overview
```

You should see:
- Transaction rate graph showing ~10 TPS
- Success rate at 100%
- Latency percentiles (P50, P95, P99)
- Resource utilization below 10%

## 🔍 Validation Points

### 1. Transaction Success

```bash
# Check transaction completion
./verify-transactions.sh --test first-test-10tps

# Output:
Transaction Verification
=======================
Test: first-test-10tps
Duration: 60 seconds
Target TPS: 10
Actual TPS: 10.0

Transactions:
- Initiated: 600
- Completed: 600
- Failed: 0
- Success Rate: 100%

Latency:
- P50: 38ms
- P95: 68ms
- P99: 89ms
```

### 2. No Errors in Logs

```bash
# Check for errors across all services
./check-logs.sh --errors-only

# Should show:
No errors found in the last 5 minutes
```

### 3. Resource Utilization

```bash
# Check resource usage
./show-resource-usage.sh

# Expected (at 10 TPS):
Resource Usage Summary
=====================
MOJALOOP CLUSTER:
- CPU: 5-10% utilized
- Memory: 20-30% utilized
- Network: < 1 Mbps

K6 CLUSTER:
- CPU: < 5% utilized
- Memory: < 10% utilized
- Network: < 1 Mbps

✅ Plenty of headroom for scaling
```

## 🧪 Test Variations

Try these variations to build confidence:

<details>
<summary><strong>Test with Different DFSP Pairs</strong></summary>

```bash
# Test each payer-payee combination
for payer in 1 2 3 4; do
  for payee in 5 6 7 8; do
    ./run-pair-test.sh --from perffsp-$payer --to perffsp-$payee
  done
done
```

</details>

<details>
<summary><strong>Test with Varying Amounts</strong></summary>

```bash
# Test different transaction amounts
./run-amount-test.sh --amounts "1,10,100,1000,10000"
```

</details>

<details>
<summary><strong>Test Error Scenarios</strong></summary>

```bash
# Test invalid MSISDN
./run-error-test.sh --scenario invalid-party

# Test insufficient funds
./run-error-test.sh --scenario insufficient-funds

# Verify proper error handling
```

</details>

## 🔧 Troubleshooting

<details>
<summary><strong>No transactions completing</strong></summary>

```bash
# Check end-to-end flow
./debug-transaction-flow.sh

# Common issues:
# 1. Security stack misconfigured
./verify-security.sh

# 2. DFSP not provisioned correctly
./verify-participants.sh

# 3. Network connectivity issues
./test-connectivity.sh --detailed
```

</details>

<details>
<summary><strong>High latency (>200ms)</strong></summary>

```bash
# Analyze latency breakdown
./analyze-latency.sh --test first-test-10tps

# Check for:
# - Database query times
# - Network latency between clusters
# - Service processing times
```

</details>

## ✅ Success Criteria

Before proceeding to full-scale tests, ensure:

- [ ] Single transaction test passes
- [ ] 10 TPS test runs for 1 minute without errors
- [ ] Success rate is 100%
- [ ] P95 latency < 100ms
- [ ] Metrics visible in Grafana
- [ ] No errors in service logs
- [ ] Resource utilization < 20%

## 🚀 Next Steps

### If all tests pass:
```bash
# Proceed to full performance testing
cd ../07-performance-tests
./prepare-for-scale.sh
```

### If issues found:
```bash
# Generate diagnostic report
./create-diagnostic-report.sh

# Review common issues
cat COMMON_ISSUES.md

# Get help
./show-support-info.sh
```

Ready for full-scale testing? → [Phase 07: Performance Tests](../07-performance-tests/)

---

<details>
<summary><strong>📚 Additional Resources</strong></summary>

- [Understanding Test Results](TEST_RESULTS.md)
- [Debugging Failed Tests](DEBUG_GUIDE.md)
- [K6 Script Reference](K6_SCRIPTS.md)
- [Metrics Glossary](METRICS.md)

</details>