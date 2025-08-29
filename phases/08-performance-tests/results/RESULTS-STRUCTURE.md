# Performance Test Results Directory Structure

> **Purpose**: Organize all test artifacts in a consistent, analyzable structure supporting multiple runs

## 📁 Directory Organization

Test results are organized by test type, then by timestamp for each run:

```
results/
├── 01-baseline-100tps/
│   ├── 2024-01-15-14-30-22/
│   ├── 2024-01-15-16-45-10/
│   └── 2024-01-16-09-15-33/
├── 02-scale-500tps/
│   ├── 2024-01-15-15-30-45/
│   └── 2024-01-16-10-20-15/
├── 03-target-1000tps/
│   ├── 2024-01-15-16-35-12/
│   ├── 2024-01-16-11-30-22/  # First attempt
│   ├── 2024-01-16-14-15-45/  # After tuning
│   └── 2024-01-17-09-45-18/  # Final successful run
├── 04-endurance-1000tps/
│   └── 2024-01-17-14-30-00/
├── 05-stress-to-failure/
│   └── 2024-01-17-17-45-30/
├── aggregated/                 # Cross-test analysis
└── RESULTS-STRUCTURE.md       # This file
```

## 🗂️ Test Run Structure

Each timestamped run directory contains:

### 1. K6 Raw Data (`k6-raw-data/`)
Raw, unprocessed K6 output for detailed analysis:
- `k6-output.log` - Complete stdout/stderr from K6
- `k6-metrics.json` - All metrics in JSON format
- `k6-thresholds.json` - Pass/fail threshold results
- `k6-iterations.csv` - Per-iteration data (if enabled)

### 2. K6 Summaries (`k6-summaries/`)
Processed summaries for quick review:
- `summary.txt` - Human-readable test summary
- `summary.json` - Machine-readable summary
- `checks.json` - All check results with pass rates
- `end-of-test.json` - Final test state

### 3. Metrics (`metrics/`)
Time-series data for trending:
```
metrics/
├── prometheus/           # Prometheus exports
│   ├── mojaloop_transfers_total.json
│   ├── mojaloop_transfers_duration.json
│   ├── k6_http_reqs_total.json
│   └── k6_vus.json
└── service-level/       # Per-service breakdowns
    ├── ml-api-adapter.json
    ├── central-ledger.json
    ├── account-lookup.json
    └── quote-service.json
```

### 4. Resource Utilization (`resource-utilization/`)
Infrastructure metrics during test:
```
resource-utilization/
├── cpu/
│   ├── nodes.json         # CPU % per node over time
│   ├── services.json      # CPU per service
│   └── top-consumers.json # Highest CPU users
├── memory/
│   ├── nodes.json         # Memory usage per node
│   ├── services.json      # Memory per service
│   └── oom-events.json    # OOM kill events
├── network/
│   ├── throughput.json    # Mbps in/out
│   ├── connections.json   # Connection counts
│   └── latency.json       # Network latency
└── disk/
    ├── iops.json          # Read/write IOPS
    ├── throughput.json    # MB/s throughput
    └── queue-depth.json   # Disk queue metrics
```

### 5. Grafana Dashboards (`grafana-dashboards/`)
Visual evidence of performance:
```
grafana-dashboards/
├── performance-overview/
│   ├── 01-test-start.png      # Initial state
│   ├── 02-ramp-up.png         # During ramp
│   ├── 03-peak-tps.png        # Peak achievement
│   ├── 04-steady-state.png    # Sustained performance
│   └── 05-test-end.png        # Final state
├── service-health/
│   ├── ml-api-adapter-peak.png
│   ├── central-ledger-peak.png
│   ├── account-lookup-peak.png
│   └── all-services-1000tps.png
├── infrastructure/
│   ├── cpu-utilization-timeline.png
│   ├── memory-usage-timeline.png
│   ├── network-traffic-peak.png
│   └── node-pressure.png
├── k6-metrics/
│   ├── vus-timeline.png       # Virtual users
│   ├── request-rate.png       # Requests/sec
│   ├── response-time.png      # Latency distribution
│   └── error-rate.png         # Errors over time
└── custom/                     # Special captures
    ├── interesting-anomaly.png
    └── bottleneck-evidence.png
```

### 6. Logs (`logs/`)
Detailed logs for debugging:
```
logs/
├── k6/
│   ├── runner.log         # K6 runner logs
│   └── coordinator.log    # If using distributed K6
├── mojaloop-services/
│   ├── ml-api-adapter.log
│   ├── central-ledger.log
│   └── errors-only.log    # Filtered error logs
└── infrastructure/
    ├── node-events.log    # Kubernetes node events
    └── pod-events.log     # Pod scheduling/failures
```

### 7. Analysis (`analysis/`)
Post-test analysis outputs:
```
analysis/
├── bottlenecks/
│   ├── identified-bottlenecks.json
│   ├── bottleneck-timeline.png
│   └── recommendations.md
├── errors/
│   ├── error-classification.json
│   ├── error-timeline.png
│   └── root-cause-analysis.md
└── trends/
    ├── latency-trend.json
    ├── throughput-trend.json
    └── resource-trend.json
```

### 8. Configuration Snapshots (`config-snapshots/`)
Configuration at test time:
- `k6-test.yaml` - K6 test configuration
- `mojaloop-values.yaml` - Helm values used
- `infrastructure.json` - Node types, counts
- `service-replicas.json` - Scaling configuration
- `resource-limits.json` - Resource constraints

## 📊 Aggregated Results

The `aggregated/` directory contains cross-test analysis:

```
aggregated/
├── comparison/
│   ├── tps-progression.json      # TPS across all tests
│   ├── latency-comparison.json   # Latency trends
│   ├── resource-efficiency.json  # Resource per TPS
│   └── cost-analysis.json        # Cost per million txns
└── reports/
    ├── executive-summary.pdf     # High-level results
    ├── technical-report.pdf      # Detailed analysis
    └── tuning-insights.md        # Lessons learned
```

## 🔧 Usage

### During Test Execution
```bash
# Create timestamped directory for this run
export TEST_TYPE="03-target-1000tps"
export TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
export TEST_DIR="results/$TEST_TYPE/$TIMESTAMP"
mkdir -p "$TEST_DIR"/{k6-raw-data,k6-summaries,metrics,resource-utilization,grafana-dashboards,logs,analysis,config-snapshots}

# Capture K6 output
kubectl logs -f k6-target-test > "$TEST_DIR/k6-raw-data/k6-output.log"

# Export K6 metrics
kubectl exec k6-target-test -- k6 stats export > "$TEST_DIR/k6-raw-data/k6-metrics.json"

# Take dashboard screenshots and save to:
# $TEST_DIR/grafana-dashboards/performance-overview-peak-tps.png
# $TEST_DIR/grafana-dashboards/service-health-1000tps.png
# $TEST_DIR/grafana-dashboards/resource-utilization.png
```

### Manual Data Collection
```bash
# K6 Summary
kubectl logs k6-target-test --tail=200 > "$TEST_DIR/k6-summaries/summary.txt"

# Resource snapshots
kubectl top nodes > "$TEST_DIR/resource-utilization/nodes-snapshot.txt"
kubectl top pods -n mojaloop > "$TEST_DIR/resource-utilization/pods-snapshot.txt"

# Service logs
kubectl logs -n mojaloop -l app=ml-api-adapter --tail=1000 > "$TEST_DIR/logs/ml-api-adapter.log"

# Configuration snapshots
helm get values mojaloop -n mojaloop > "$TEST_DIR/config-snapshots/mojaloop-values.yaml"
```

## 📋 Checklist for Complete Results

For each test, ensure you have:

- [ ] K6 raw output log
- [ ] K6 metrics JSON export
- [ ] K6 summary (text and JSON)
- [ ] Prometheus metrics for test duration
- [ ] Service-level metrics breakdown
- [ ] Resource utilization data (CPU, memory, network, disk)
- [ ] Grafana screenshots at key moments:
  - [ ] Test start
  - [ ] Peak TPS achievement
  - [ ] Steady state
  - [ ] Test end
- [ ] Service logs (at least last 30 minutes)
- [ ] Configuration snapshots
- [ ] Initial analysis outputs

## 🎯 Best Practices

1. **Immediate Capture**: Take screenshots as soon as important moments occur
2. **Descriptive Names**: Use clear filenames like `1000tps-achieved-1547.png`
3. **Time Alignment**: Note exact timestamps for correlating data
4. **Raw Data First**: Always capture raw data; process later
5. **Automation**: Use scripts to avoid missing data during critical moments

## 🔄 Data Retention

- **Raw Data**: Keep for 30 days minimum
- **Summaries**: Keep indefinitely
- **Screenshots**: Keep best examples indefinitely
- **Aggregated Reports**: Keep indefinitely

## 📤 Sharing Results

To package results for sharing:
```bash
# Package single test
tar -czf target-1000tps-results.tar.gz results/03-target-1000tps/

# Package all results
tar -czf mojaloop-perf-results.tar.gz results/
```