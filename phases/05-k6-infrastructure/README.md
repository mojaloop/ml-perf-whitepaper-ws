# Phase 05: K6 Testing Infrastructure

> **Purpose**: Deploy isolated K6 infrastructure for load generation
> 
> **Time Required**: 1-2 hours
> 
> **Outcome**: Dedicated K6 cluster ready to generate 1000+ TPS

## 🎯 Why Isolated K6 Infrastructure?

<details>
<summary><strong>The Problem with Shared Infrastructure</strong></summary>

Running K6 on the same cluster as Mojaloop:
- **Skews Metrics**: Load generation consumes CPU/memory that affects measurements
- **Resource Competition**: K6 and Mojaloop fight for resources
- **Network Congestion**: Internal cluster networking becomes a bottleneck
- **Inaccurate Results**: Can't distinguish between load generation and processing overhead

</details>

**The Solution**: Dedicated K6 cluster with:
- Separate compute resources
- Independent network path
- Isolated monitoring
- Guaranteed performance

### K6 Testing Architecture

![K6 Testing Architecture](diagrams/k6-testing-architecture.svg)
*Isolated K6 infrastructure with VPC peering to Mojaloop*

## 📋 Pre-deployment Checks

```bash
# Switch to K6 cluster
kubectl config use-context k6

# Verify cluster is ready
kubectl get nodes

# Check connectivity to Mojaloop
./test-connectivity.sh

# Expected:
Connectivity Test
=================
✅ K6 cluster nodes: 8 ready
✅ Mojaloop API endpoint: Reachable
✅ VPC peering: Active
✅ Security groups: Configured
```

## 🚀 Deploy K6 Infrastructure

### Quick Deployment

```bash
# Deploy K6 operator and infrastructure
./deploy.sh

# Monitor deployment
watch kubectl get pods -n k6-operator
```

### Components Deployed

```yaml
k6-operator:
  - k6-operator-controller-manager
  - k6-operator-webhook-service

k6-tests:
  - test-data-generator
  - result-aggregator
  - grafana-k6-dashboards

monitoring:
  - prometheus-k6
  - grafana
```

## 🏗️ K6 Worker Configuration

### Resource Allocation for Different TPS Targets

| Target TPS | Workers | CPU/Worker | Memory/Worker | Total Resources |
|------------|---------|------------|---------------|-----------------|
| 100 | 2 | 2 cores | 4Gi | 4 CPU, 8Gi |
| 500 | 5 | 4 cores | 8Gi | 20 CPU, 40Gi |
| 1000 | 8 | 4 cores | 8Gi | 32 CPU, 64Gi |
| 5000 | 20 | 8 cores | 16Gi | 160 CPU, 320Gi |

### Configure Workers

```bash
# Apply worker configuration for 1000 TPS
kubectl apply -f configs/workers-1000tps.yaml

# Scale workers if needed
kubectl scale deployment k6-workers --replicas=10
```

## 📊 Test Scenarios

### Available Test Configurations

<details>
<summary><strong>1. Baseline Test (100 TPS)</strong></summary>

```yaml
# scenarios/baseline-100tps.yaml
spec:
  parallelism: 2
  script:
    configMap:
      name: mojaloop-baseline-test
  arguments: --vus=100 --duration=5m
  
# Run test
kubectl apply -f scenarios/baseline-100tps.yaml
```

</details>

<details>
<summary><strong>2. Standard Test (1000 TPS)</strong></summary>

```yaml
# scenarios/standard-1000tps.yaml
spec:
  parallelism: 8
  script:
    configMap:
      name: mojaloop-standard-test
  arguments: --vus=1000 --duration=30m
  
# Run test
kubectl apply -f scenarios/standard-1000tps.yaml
```

</details>

<details>
<summary><strong>3. Stress Test (Ramp to Failure)</strong></summary>

```yaml
# scenarios/stress-test.yaml
spec:
  parallelism: 20
  script:
    configMap:
      name: mojaloop-stress-test
  arguments: --stages="10m:1000,10m:2000,10m:5000"
```

</details>

## 🔧 K6 Test Scripts

### P2P Transfer Test

```javascript
// Loaded from ConfigMap: mojaloop-test-scripts
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  scenarios: {
    contacts: {
      executor: 'constant-arrival-rate',
      rate: 1000, // 1000 RPS
      timeUnit: '1s',
      duration: '30m',
      preAllocatedVUs: 2000,
    },
  },
};

export default function() {
  // Test implementation for Mojaloop P2P transfers
  // Uses the 8 DFSPs with asymmetric load distribution
}
```

## 🔍 Validation

```bash
# Run validation
./validate.sh

# Expected output:
K6 Infrastructure Validation
===========================
✅ K6 Operator: Running
✅ Workers: 8/8 ready
✅ Test ConfigMaps: Loaded
✅ Prometheus: Configured for remote write
✅ Network path to Mojaloop: < 1ms latency

Load Generation Capacity:
- Current: 1200 TPS capable
- Maximum: 5000 TPS (with scaling)

🎉 K6 infrastructure ready for testing!
```

## 📈 Monitoring K6 Tests

### Access K6 Dashboards

```bash
# Get Grafana URL
./get-dashboard-url.sh

# Or port-forward
kubectl port-forward -n monitoring svc/grafana-k6 3001:80
# Access at http://localhost:3001
```

### Key Dashboards
1. **K6 Test Overview**: Real-time TPS, response times, error rates
2. **K6 Resource Usage**: CPU/memory per worker
3. **Network Metrics**: Bandwidth utilization, packet loss
4. **Test Comparison**: Compare multiple test runs

## 🧪 Run Your First Test

### Quick Validation Test

```bash
# Run a 1-minute validation test
./run-test.sh --name validation --tps 100 --duration 1m

# Monitor progress
kubectl logs -f k6-validation-test

# Expected output:
running (1m00.0s), 100/100 VUs, 6000 complete iterations
RPS: 100.0 | Success Rate: 100% | P95 Latency: 45ms
```

## 🔧 Troubleshooting

<details>
<summary><strong>K6 test pods failing to start</strong></summary>

```bash
# Check K6 operator logs
kubectl logs -n k6-operator deployment/k6-operator-controller-manager

# Common issue: ConfigMap not found
kubectl get configmap -n k6-tests

# Fix: Recreate test scripts
./deploy-test-scripts.sh
```

</details>

<details>
<summary><strong>Can't reach Mojaloop endpoints</strong></summary>

```bash
# Test connectivity from K6 pod
kubectl run test-curl --image=curlimages/curl --rm -it -- sh
curl -v http://mojaloop-api.mojaloop.local/health

# Check VPC peering
aws ec2 describe-vpc-peering-connections

# Verify security groups
./verify-security-groups.sh
```

</details>

## ✅ Completion Checklist

- [ ] K6 operator deployed and running
- [ ] Worker nodes configured for target TPS
- [ ] Test scripts loaded in ConfigMaps
- [ ] Connectivity to Mojaloop verified
- [ ] Monitoring dashboards accessible

## 🚀 Next Step

Ready to run your first real test:

```bash
# Quick test to verify everything works
./run-test.sh --name first-test --tps 10 --duration 30s

# Check results
kubectl logs k6-first-test
```

Continue to → [Phase 06: First Test Run](../06-first-test/)

---

<details>
<summary><strong>📚 Additional Resources</strong></summary>

- [K6 Script Development](SCRIPT_GUIDE.md)
- [Load Distribution Strategies](LOAD_PATTERNS.md)
- [Network Optimization](NETWORK_TUNING.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)

</details>