# K6 Testing Infrastructure

Isolated infrastructure for K6 load generation to ensure test traffic doesn't impact Mojaloop switch performance measurements.

## Directory Structure

- **terraform/**: Infrastructure as code for K6 cluster
- **deployment/**: K6 operator and test runner deployments
- **worker-configs/**: Configuration for K6 worker nodes

## Architecture

### Isolation Strategy

1. **Separate EKS Cluster**: Dedicated cluster for K6 workloads
2. **VPC Peering**: Connected to Mojaloop VPC via peering
3. **Resource Allocation**: Guaranteed resources for consistent load generation
4. **Network Bandwidth**: Dedicated network capacity

### Components

1. **K6 Operator/Helm**: Manages test execution
2. **Test Runners**: Distributed K6 executors
3. **Metrics Collection**: Prometheus remote write
4. **Result Storage**: S3 for test artifacts

## Deployment

1. Provision infrastructure:
   ```bash
   cd terraform
   terraform apply
   ```

2. Deploy K6 operator:
   ```bash
   kubectl apply -f deployment/k6-operator.yaml
   ```

3. Configure workers:
   ```bash
   kubectl apply -f worker-configs/
   ```

## Scaling Guidelines

For different TPS targets:
- **100 TPS**: 1-2 worker nodes
- **500 TPS**: 3-5 worker nodes
- **1000 TPS**: 5-8 worker nodes
- **5000 TPS**: 20+ worker nodes

## Resource Requirements

Per worker node:
- **CPU**: 8 vCPUs minimum
- **Memory**: 16GB RAM
- **Network**: 10 Gbps bandwidth
- **Storage**: 100GB SSD

## Performance Tuning

Document K6 configuration optimizations for high TPS scenarios.
