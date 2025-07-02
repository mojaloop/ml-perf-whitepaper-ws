# Performance Tuning Playbook

> **Reality Check**: Didn't hit 1000 TPS on your first try? That's normal! This playbook guides you through systematic tuning to reach your target.

## 🎯 Quick Decision Tree

```
Current TPS < 500?
├─ Yes → Start with [Infrastructure Scaling](#infrastructure-scaling)
└─ No → Current TPS < 800?
    ├─ Yes → Focus on [Mojaloop Tuning](#mojaloop-tuning)
    └─ No → Fine-tune with [Advanced Optimizations](#advanced-optimizations)
```

## 📊 Diagnose the Bottleneck

Before tuning anything, identify WHERE the bottleneck is:

```bash
# Run the bottleneck analyzer
./scripts/analyze-bottleneck.sh --target-tps 1000

# Example output:
Bottleneck Analysis for 1000 TPS Target
========================================
Current Achievement: 623 TPS (62% of target)

BOTTLENECKS IDENTIFIED:
1. CPU Saturation on ml-api-adapter (92% usage) ← PRIMARY
2. Database connection pool (78% utilized) ← SECONDARY  
3. Kafka consumer lag (increasing) ← TERTIARY

RECOMMENDATIONS:
→ Scale ml-api-adapter horizontally
→ Increase database connections
→ Add Kafka partitions
```

## 🔧 Infrastructure Scaling

> **When to use**: TPS < 500 or infrastructure metrics show saturation

### Quick Wins First

```bash
# 1. Check if we're using all available resources
./scripts/check-resource-utilization.sh

# Often finds:
# - CPU limits preventing full utilization
# - Memory not being used effectively
# - Network bandwidth available
```

### Scale Mojaloop Cluster Nodes

```bash
# Go back to Phase 02 and modify infrastructure
cd ../../02-infrastructure

# Edit terraform/eks-mojaloop/variables.tf
# Change from c5.4xlarge to c5.9xlarge (or add more nodes)
```

**Option 1: Vertical Scaling (Bigger Instances)**
```hcl
# terraform/eks-mojaloop/variables.tf
variable "node_instance_type" {
  default = "c5.9xlarge"  # Was c5.4xlarge
}

# Apply changes
cd terraform
terraform plan -target=module.eks_mojaloop
terraform apply -target=module.eks_mojaloop
```

**Option 2: Horizontal Scaling (More Nodes)**
```hcl
# terraform/eks-mojaloop/node-groups.tf
resource "aws_eks_node_group" "mojaloop" {
  scaling_config {
    desired_size = 20  # Was 15
    max_size     = 30  # Was 20
    min_size     = 15  # Was 10
  }
}
```

**Option 3: Mixed Instance Types (Cost Optimization)**
```hcl
# Use spot instances for some workloads
instance_types = ["c5.4xlarge", "c5a.4xlarge", "m5.4xlarge"]
capacity_type  = "SPOT"
spot_instance_pools = 3
```

### Scale K6 Infrastructure

```bash
# If K6 is the bottleneck (rare but happens)
cd ../../05-k6-infrastructure

# Add more K6 workers
kubectl scale deployment k6-workers -n k6 --replicas=16
```

### Post-Scaling Validation

```bash
# After infrastructure changes, verify:
./scripts/validate-infrastructure-scaling.sh

# Re-run Mojaloop deployment to use new resources
cd ../../04-mojaloop
./scripts/update-resource-allocations.sh
```

## 🚀 Mojaloop Tuning

> **When to use**: TPS between 500-800, infrastructure has headroom

### Service-Specific Scaling

Based on bottleneck analysis, scale specific services:

```bash
# Return to Phase 04
cd ../../04-mojaloop

# Edit helm-values/values-performance.yaml
```

**1. ML-API-Adapter (Usually the first bottleneck)**
```yaml
ml-api-adapter:
  replicaCount: 20  # Increase from 12
  resources:
    requests:
      cpu: 4
      memory: 8Gi
    limits:
      cpu: 8      # Or remove limits entirely
      memory: 16Gi
```

**2. Central-Ledger Handlers**
```yaml
central-ledger:
  handlers:
    # Position handler handles account updates
    position:
      replicaCount: 10  # Increase from 5
    # Notification handler sends callbacks  
    notification:
      replicaCount: 8   # Increase from 4
    # Transfer handler processes fulfillments
    transfer:
      replicaCount: 12  # Increase from 6
```

**3. Database Connections**
```yaml
central-ledger:
  config:
    db:
      connection:
        pool:
          min: 50        # Increase from 10
          max: 300       # Increase from 100
          acquireTimeoutMillis: 30000
```

**4. Kafka Optimizations**
```yaml
kafka:
  config:
    # Increase partitions for parallel processing
    num.partitions: 30  # From 10
    # Optimize for throughput
    compression.type: lz4
    batch.size: 65536
```

### Apply Mojaloop Changes

```bash
# Update Mojaloop with new settings
helm upgrade mojaloop mojaloop/mojaloop \
  -f helm-values/values-performance.yaml \
  -n mojaloop \
  --wait

# Monitor rollout
watch kubectl get pods -n mojaloop

# Verify changes applied
./scripts/verify-scaling-applied.sh
```

### Handler-Specific Tuning

**Position Handler Optimization**
```bash
# Position handler often bottlenecks on batch processing
kubectl set env deployment/central-ledger-handler-position -n mojaloop \
  POSITION_BATCH_SIZE=200 \
  POSITION_BATCH_INTERVAL_MS=100
```

**Notification Handler Optimization**
```bash
# Notification handler can bottleneck on callback sending
kubectl set env deployment/central-ledger-handler-notification -n mojaloop \
  NOTIFICATION_CONCURRENT_REQUESTS=50 \
  NOTIFICATION_TIMEOUT_MS=5000
```

## 🎛️ Advanced Optimizations

> **When to use**: TPS > 800 but still short of 1000

### Database Optimizations

```bash
# Connect to RDS instance
cd ../../02-infrastructure
./scripts/connect-to-rds.sh

# Apply performance optimizations
mysql -h $RDS_ENDPOINT -u admin -p$RDS_PASSWORD << EOF
-- Increase connections
SET GLOBAL max_connections = 500;

-- Optimize for high concurrency
SET GLOBAL innodb_thread_concurrency = 0;
SET GLOBAL innodb_read_io_threads = 64;
SET GLOBAL innodb_write_io_threads = 64;

-- Increase buffer pool
SET GLOBAL innodb_buffer_pool_size = 48G;
EOF
```

### Network Optimizations

```bash
# Enable enhanced networking if not already
cd ../../02-infrastructure/terraform
# Add to instance configuration
ena_support = true
```

### Service Mesh Tuning

```bash
# Optimize Istio for performance
cd ../../03-kubernetes
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio-custom
  namespace: istio-system
data:
  custom.yaml: |
    defaultConfig:
      concurrency: 4
      proxyStatsMatcher:
        inclusionRegexps:
        - ".*circuit_breakers.*"
        - ".*osconfig.*"
        inclusionPrefixes:
        - "cluster.outbound"
        - "cluster.inbound"
EOF
```

## 📈 Iterative Tuning Process

### The Tuning Loop

```
1. Run Test (Phase 07)
   ↓
2. Analyze Results (Phase 08) 
   ↓
3. Identify Bottleneck ←─────┐
   ↓                         │
4. Apply Fix:                │
   - Infrastructure (02) ────┤
   - Kubernetes (03) ────────┤
   - Mojaloop (04) ──────────┘
   ↓
5. Re-run Test → Back to 1
```

### Tracking Progress

```bash
# After each tuning iteration
./scripts/record-tuning-progress.sh \
  --iteration 3 \
  --change "Scaled ML-API to 20 replicas" \
  --result "750 TPS achieved"

# View tuning history
./scripts/show-tuning-history.sh

# Example output:
Tuning History
==============
Iteration 1: Baseline → 450 TPS
Iteration 2: +8 nodes → 623 TPS  
Iteration 3: +ML-API replicas → 750 TPS
Iteration 4: +DB connections → 890 TPS
Iteration 5: +Kafka partitions → 1,024 TPS ✓
```

## 🎯 Tuning Cheat Sheet

| Current TPS | Most Likely Bottleneck | Quick Fix |
|-------------|------------------------|-----------|
| < 200 | Infrastructure undersized | Add nodes or bigger instances |
| 200-400 | CPU limits too low | Remove CPU limits |
| 400-600 | Not enough service replicas | Scale ML-API and handlers |
| 600-800 | Database connections | Increase pool size |
| 800-950 | Kafka partitions | Add partitions and consumers |
| 950-990 | Fine tuning needed | Optimize batch sizes |

## 🚨 When to Stop Tuning

Stop when you achieve ANY of these:
1. ✅ Target TPS reached (1000+)
2. ⚠️ Costs exceed budget
3. 🔴 Diminishing returns (10% improvement costs 50% more)

## 💡 Cost-Aware Tuning

```bash
# Before each infrastructure change
./scripts/estimate-cost-impact.sh \
  --current c5.4xlarge \
  --proposed c5.9xlarge \
  --nodes 20

# Output:
Cost Impact Analysis
===================
Current: $368/day
Proposed: $592/day
Increase: $224/day (61%)
Expected TPS gain: 350 (56%)
Cost per TPS: $0.64/TPS
```

## 📊 Document Your Results

After achieving target:

```bash
# Generate tuning report
cd ../../08-analysis
./scripts/generate-tuning-report.sh

# Creates a report showing:
# - Starting vs final configuration
# - Each tuning step and impact
# - Cost analysis
# - Recommendations for production
```

Remember: Most deployments need 2-3 tuning iterations to hit 1000 TPS. That's normal and expected!