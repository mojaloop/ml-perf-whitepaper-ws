# Infrastructure Architecture Decisions

> **Why these choices?** Every decision optimizes for achieving 1000 TPS with accurate measurements.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Account                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────┐    ┌─────────────────────────┐    │
│  │   Mojaloop VPC          │    │   K6 Testing VPC        │    │
│  │   10.0.0.0/16          │    │   10.1.0.0/16          │    │
│  │                        │    │                        │    │
│  │  ┌─────────────────┐  │    │  ┌─────────────────┐  │    │
│  │  │ EKS Cluster     │  │◄───┤  │ K6 EKS Cluster │  │    │
│  │  │ 15 x c5.4xlarge│  │    │  │ 8 x t3.2xlarge │  │    │
│  │  └─────────────────┘  │ VPC│  └─────────────────┘  │    │
│  │                        │Peer│                        │    │
│  │  ┌─────────────────┐  │    │  ┌─────────────────┐  │    │
│  │  │ RDS MySQL      │  │    │  │ Network LB      │  │    │
│  │  │ db.r5.2xlarge  │  │    │  │ (For K6 metrics)│  │    │
│  │  └─────────────────┘  │    │  └─────────────────┘  │    │
│  │                        │    │                        │    │
│  │  ┌─────────────────┐  │    └────────────────────────┘    │
│  │  │ ElastiCache    │  │                                   │
│  │  │ Redis Cluster  │  │         ┌────────────────┐       │
│  │  └─────────────────┘  │         │ S3 Buckets    │       │
│  │                        │         │ - Test Results │       │
│  └────────────────────────┘         │ - Logs         │       │
│                                     └────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

## 🤔 Key Architecture Decisions

### 1. Why Two Separate EKS Clusters?

**The Problem**: Running K6 on the same cluster as Mojaloop creates:
- Resource competition (CPU, memory, network)
- Noisy neighbor effects
- Inaccurate performance measurements
- Network congestion on cluster CNI

**The Solution**: Dedicated K6 cluster ensures:
- ✅ Clean performance measurements
- ✅ No resource competition
- ✅ Independent scaling
- ✅ Realistic network latency

**Trade-off**: Higher cost (~$60/day) but essential for accurate results.

### 2. Why c5.4xlarge for Mojaloop?

**Requirements Analysis**:
```
At 1000 TPS with 8 DFSPs:
- CPU needed: ~120 vCPUs total
- Memory needed: ~240GB total
- Network: 10 Gbps minimum
```

**c5.4xlarge provides**:
- 16 vCPUs (compute optimized)
- 32 GB RAM
- Up to 10 Gbps network
- Best price/performance for CPU-intensive workloads

**Why not**:
- m5.4xlarge: More expensive, unnecessary memory
- c5.2xlarge: Would need 2x more nodes
- c6i.4xlarge: 20% more expensive, marginal benefit

### 3. Why RDS Instead of Self-Managed MySQL?

**Benefits**:
- Automated backups during tests
- Multi-AZ failover capability
- Performance Insights included
- No node resources used for database

**Sizing**: db.r5.2xlarge chosen for:
- 8 vCPUs for parallel query processing
- 64 GB RAM for connection pooling (1000+ connections)
- 10 Gbps network to handle transaction volume

### 4. VPC Design Decisions

**Separate VPCs because**:
- Security isolation
- Independent CIDR management
- Clear cost allocation
- Easier cleanup

**CIDR Choices**:
- 10.0.0.0/16 (Mojaloop): 65,534 IPs for service expansion
- 10.1.0.0/16 (K6): Separate range prevents conflicts

**Peering over Transit Gateway because**:
- Lower latency (single hop)
- Lower cost for 2 VPCs
- Simpler configuration

### 5. Why These Availability Zones?

**3 AZs for Mojaloop** (us-west-2a,b,c):
- EKS requires minimum 2 AZs
- 3 provides better capacity availability
- Spreads risk of AZ capacity issues

**2 AZs for K6** (us-west-2a,b):
- Lower cost
- K6 is stateless, less AZ redundancy needed

## 💰 Cost Optimization Decisions

### Instance Reservations
Not used because:
- Test environment is temporary
- Flexibility more important than savings
- Can be destroyed between test runs

### Spot Instances
Used for K6 cluster only:
- K6 workers are stateless
- 70% cost savings
- Interruption tolerance via multiple instance types

### Data Transfer Optimization
- VPC endpoints for S3: Avoid NAT gateway charges
- Single-AZ RDS during tests: Reduce cross-AZ transfer
- Compression enabled on all logs

## 🔐 Security Architecture

### Network Security
```
Internet → ALB → Mojaloop VPC → Private Subnets → Pods
                      ↑
                VPC Peering
                      ↑
            K6 VPC → Private Subnets → K6 Pods
```

### Security Groups
- **Principle of Least Privilege**: Only required ports open
- **Layered Security**: SG at instance and pod level
- **No Direct Internet Access**: All compute in private subnets

## 📊 Scalability Considerations

### Horizontal Scaling Limits
- **EKS Nodes**: Up to 100 per cluster
- **Pods per Node**: ~110 with current CNI
- **Total Pods**: ~1,650 possible

### Vertical Scaling Options
If need more than 1000 TPS:
1. Scale to c5.9xlarge (36 vCPUs)
2. Add more nodes
3. Consider c5n.* for network optimization

## 🚀 Performance Optimizations

### Network Performance
- **Placement Groups**: Cluster placement for low latency
- **Enhanced Networking**: SR-IOV enabled
- **Jumbo Frames**: 9000 MTU within VPC

### Storage Performance
- **GP3 EBS**: 3000 IOPS baseline, burstable to 16,000
- **Local NVMe**: For temporary K6 test data

## 📋 Disaster Recovery

### State Management
- Terraform state in S3 with versioning
- State locking via DynamoDB
- Automated backups every hour during tests

### Recovery Time Objectives
- **Infrastructure Recreation**: 45 minutes
- **Data Recovery**: 15 minutes (from snapshots)
- **Full Environment**: 2 hours

## 🔄 Alternative Architectures Considered

### Single Cluster Approach
❌ **Rejected because**:
- Inaccurate performance measurements
- Resource competition
- Complex resource quotas needed

### Fargate for K6
❌ **Rejected because**:
- Limited CPU (4 vCPU max per task)
- Higher cost at scale
- Less control over placement

### Self-Managed Kubernetes
❌ **Rejected because**:
- Longer setup time
- Maintenance overhead
- EKS provides better integration

## 📚 References

- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Mojaloop Deployment Guide](https://docs.mojaloop.io/documentation/deployment-guide/)