# Performance Testing Troubleshooting

> **Quick Check**: If TPS is below target, run `./scripts/find-bottleneck.sh` - it identifies 90% of issues automatically!

## 🔴 Common Performance Issues

### TPS Plateaus Below Target

**Symptoms:**
- Stuck at 200-300 TPS when targeting 1000
- K6 shows "waiting for available VU"
- Response times increasing linearly

**Quick Diagnosis:**
```bash
# Real-time bottleneck detection
./scripts/find-bottleneck.sh --live

# Check K6 capacity
kubectl top pods -n mojaloop -l k6.io/name=performance-test

# Service saturation
./scripts/check-service-saturation.sh
```

**Common Bottlenecks & Fixes:**

#### 1. Database Connection Pool Exhausted
**Identify:**
```bash
# Check connection usage
kubectl exec -n mojaloop deployment/mysql -- \
  mysql -u root -p$MYSQL_ROOT_PASSWORD -e \
  "SHOW STATUS LIKE 'Threads_connected';"

# Look for connection errors
kubectl logs -n mojaloop deployment/central-ledger | grep -i "connection.*pool"
```

**Fix:**
```bash
# Increase pool size
kubectl set env deployment/central-ledger -n mojaloop \
  DATABASE_POOL_MIN=100 \
  DATABASE_POOL_MAX=300 \
  DATABASE_POOL_ACQUIRE_TIMEOUT=10000

# Also update MySQL max connections
kubectl exec -n mojaloop deployment/mysql -- \
  mysql -u root -p$MYSQL_ROOT_PASSWORD -e \
  "SET GLOBAL max_connections = 500;"
```

#### 2. Kafka Lag Building Up
**Identify:**
```bash
# Check consumer lag
kubectl exec -n mojaloop kafka-0 -- \
  kafka-consumer-groups --bootstrap-server localhost:9092 \
  --describe --all-groups | grep LAG

# Monitor topic throughput
./scripts/monitor-kafka-throughput.sh
```

**Fix:**
```bash
# Increase partitions
for topic in topic-transfer-prepare topic-transfer-fulfill; do
  kubectl exec -n mojaloop kafka-0 -- \
    kafka-topics --bootstrap-server localhost:9092 \
    --alter --topic $topic --partitions 20
done

# Scale consumers
kubectl scale deployment -n mojaloop ml-handler-notification --replicas=10
kubectl scale deployment -n mojaloop central-handler --replicas=8
```

#### 3. CPU Throttling
**Identify:**
```bash
# Check CPU throttling
kubectl top pods -n mojaloop --sort-by=cpu

# Detailed throttling metrics
for pod in $(kubectl get pods -n mojaloop -o name); do
  kubectl exec $pod -- cat /sys/fs/cgroup/cpu/cpu.stat 2>/dev/null | grep throttled
done
```

**Fix:**
```bash
# Remove CPU limits (for testing)
./scripts/remove-cpu-limits.sh --namespace mojaloop

# Or increase limits
kubectl patch deployment ml-api-adapter -n mojaloop --patch '
spec:
  template:
    spec:
      containers:
      - name: ml-api-adapter
        resources:
          limits:
            cpu: "8"
          requests:
            cpu: "4"'
```

---

### High Latency Spikes

**Symptoms:**
- P95 latency > 1000ms
- Intermittent timeouts
- Sawtooth pattern in metrics

**Investigation:**
```bash
# Trace slow requests
./scripts/trace-slow-requests.sh --threshold 500ms

# Check GC pauses
kubectl logs -n mojaloop deployment/central-ledger | grep -i "gc pause"

# Network latency between clusters
./scripts/measure-network-latency.sh
```

**Common Causes:**

#### 1. Garbage Collection
```bash
# Add GC logging
kubectl set env deployment/central-ledger -n mojaloop \
  NODE_OPTIONS="--expose-gc --trace-gc"

# Use better GC settings
kubectl set env deployment/central-ledger -n mojaloop \
  NODE_OPTIONS="--max-old-space-size=8192 --max-semi-space-size=256"
```

#### 2. Database Lock Contention
```bash
# Check for locks
kubectl exec -n mojaloop deployment/mysql -- \
  mysql -u root -p$MYSQL_ROOT_PASSWORD -e \
  "SHOW ENGINE INNODB STATUS\G" | grep -A20 "LATEST DETECTED DEADLOCK"

# Optimize queries
./scripts/analyze-slow-queries.sh
```

---

### K6 Load Generation Issues

**Symptoms:**
- K6 can't generate target load
- "Insufficient VUs" errors
- K6 workers OOM killed

#### Not Enough VUs
```bash
# Check VU allocation
kubectl logs -n mojaloop k6-performance-test | grep "VUs"

# Increase VUs
kubectl patch testrun performance-test -n mojaloop --patch '
spec:
  parallelism: 20
  separate: true
  arguments: --vus=5000 --max-vus=10000'
```

#### K6 Network Bottleneck
```bash
# Check K6 cluster network
kubectl exec -n k6 deployment/k6-workers -- ifconfig | grep "RX bytes"

# Add more K6 workers
kubectl scale deployment -n k6 k6-workers --replicas=16
```

---

## 📊 Real-time Performance Monitoring

### Critical Metrics Dashboard

```bash
# Open performance dashboard
./scripts/open-dashboard.sh --dashboard critical-metrics

# Or use CLI monitoring
watch -n 2 './scripts/show-critical-metrics.sh'
```

**Key Metrics to Watch:**
```
Current TPS: 847 (Target: 1000)
Success Rate: 99.2%
P95 Latency: 234ms
Active Connections: 1847

Service Saturation:
- ML-API-Adapter: 78% CPU
- Central-Ledger: 82% CPU  ⚠️
- Database: 45% connections
- Kafka: 12ms lag
```

### Performance Profiling

```bash
# Enable profiling during test
./scripts/enable-profiling.sh

# Collect profiles after spike
./scripts/collect-profiles.sh --service central-ledger

# Analyze bottlenecks
./scripts/analyze-profile.sh central-ledger-profile.cpuprofile
```

---

## 🚨 Emergency Procedures

### Test Runaway (Can't Stop)

```bash
# Force stop K6 test
kubectl delete testrun -n mojaloop --all --force

# Kill K6 processes
kubectl delete pods -n mojaloop -l k6.io/name=performance-test --force

# Clear traffic
./scripts/emergency-stop-traffic.sh
```

### System Overload

```bash
# Rapid scale down
./scripts/emergency-scale-down.sh

# Clear queues
kubectl exec -n mojaloop kafka-0 -- \
  kafka-delete-records --bootstrap-server localhost:9092 \
  --offset-json-file /tmp/delete-records.json

# Reset connections
./scripts/reset-all-connections.sh
```

---

## 💡 Performance Optimization Tips

### Pre-test Optimization

```bash
# Warm up services
./scripts/warmup-services.sh --duration 5m

# Pre-scale components
./scripts/prescale-for-load.sh --target-tps 1000

# Clear old data
./scripts/cleanup-old-data.sh
```

### During Test Optimization

```bash
# Auto-scale based on metrics
./scripts/enable-autoscaling.sh \
  --metric cpu \
  --threshold 70 \
  --min 2 \
  --max 20

# Dynamic connection pool sizing
./scripts/dynamic-pool-sizing.sh --enable
```

### Common Quick Wins

1. **Disable unnecessary logging**:
   ```bash
   kubectl set env -n mojaloop --all LOG_LEVEL=warn
   ```

2. **Increase batch sizes**:
   ```bash
   kubectl set env deployment/central-handler -n mojaloop \
     BATCH_SIZE=100 \
     BATCH_TIMEOUT_MS=50
   ```

3. **Enable connection keep-alive**:
   ```bash
   kubectl set env -n mojaloop --all \
     KEEP_ALIVE=true \
     KEEP_ALIVE_INITIAL_DELAY=30000
   ```

---

## 🔍 Deep Diagnostics

### Transaction Tracing

```bash
# Enable distributed tracing
./scripts/enable-tracing.sh

# Trace specific transaction
./scripts/trace-transaction.sh --id <transaction-id>

# Find slow transactions
./scripts/find-slow-transactions.sh --percentile 99 --last 10m
```

### Resource Analysis

```bash
# Generate resource usage report
./scripts/resource-analysis.sh --test performance-test-1000tps

# Identify resource waste
./scripts/find-overprovisioned.sh
```

---

## 📈 Achieving 1000 TPS Checklist

Before running 1000 TPS test, verify:

- [ ] Database connections >= 300
- [ ] Kafka partitions >= 20 per topic
- [ ] All services have >= 3 replicas
- [ ] CPU limits removed or >= 4 cores
- [ ] Network bandwidth verified (10 Gbps)
- [ ] K6 workers >= 8 nodes
- [ ] Monitoring dashboards open
- [ ] Emergency scripts ready

## 🆘 Still Can't Reach Target?

1. **Generate detailed analysis**:
   ```bash
   ./scripts/deep-performance-analysis.sh --target 1000
   ```

2. **Check architecture limits**:
   ```bash
   ./scripts/check-architecture-limits.sh
   ```

3. **Consider vertical scaling**:
   ```bash
   ./scripts/recommend-scaling.sh --current-tps 500 --target-tps 1000
   ```