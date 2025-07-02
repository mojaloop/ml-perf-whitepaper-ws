# Infrastructure Troubleshooting

> **Quick Fix**: 90% of infrastructure issues are AWS service limits. Run `./check-limits.sh` first!

## 🔴 Common Issues & Solutions

### EKS Cluster Creation Fails

**Symptoms:**
- CloudFormation stack stuck in `CREATE_IN_PROGRESS` for >30 minutes
- Error: "Cannot create cluster 'mojaloop-perf': AWS::EKS::Cluster"

**Diagnosis:**
```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name eksctl-mojaloop-perf-cluster \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# Check EKS service limits
aws service-quotas get-service-quota \
  --service-code eks \
  --quota-code L-1194D53C
```

**Solutions:**
1. **Insufficient EKS quota**:
   ```bash
   # Request increase
   aws service-quotas request-service-quota-increase \
     --service-code eks \
     --quota-code L-1194D53C \
     --desired-value 4
   ```

2. **Subnet capacity**:
   ```bash
   # Use different AZs
   ./deploy.sh --availability-zones us-west-2a,us-west-2c
   ```

3. **IAM role issues**:
   ```bash
   # Recreate service-linked role
   aws iam delete-service-linked-role --role-name AWSServiceRoleForAmazonEKS
   aws eks create-cluster --name temp --role-arn ... # This recreates the role
   ```

---

### Instance Launch Failures

**Symptoms:**
- Error: "Insufficient capacity" or "InsufficientInstanceCapacity"
- Nodes not joining cluster

**Quick Check:**
```bash
# See what's available in your AZs
aws ec2 describe-instance-type-offerings \
  --filters "Name=instance-type,Values=c5.4xlarge" \
  --query 'InstanceTypeOfferings[*].[InstanceType,Location]' \
  --output table
```

**Solutions:**
1. **Try different instance types**:
   ```bash
   # Edit terraform/eks-mojaloop/variables.tf
   instance_types = ["c5.4xlarge", "c5a.4xlarge", "m5.4xlarge"]
   ```

2. **Use spot instances for K6 cluster**:
   ```bash
   # Edit terraform/eks-k6/node-groups.tf
   capacity_type = "SPOT"
   spot_instance_pools = 4
   ```

---

### VPC Peering Connection Issues

**Symptoms:**
- K6 tests can't reach Mojaloop endpoints
- Timeout errors in connectivity tests

**Diagnosis:**
```bash
# Check peering status
aws ec2 describe-vpc-peering-connections \
  --filters "Name=status-code,Values=pending-acceptance,failed"

# Verify route tables
./scripts/verify-routes.sh
```

**Fix:**
```bash
# Accept pending connection
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id pcx-xxxxx

# Update route tables
./scripts/fix-routes.sh
```

---

### RDS Creation Hanging

**Symptoms:**
- RDS instance stuck in "creating" state >20 minutes
- Terraform apply hanging

**Common Causes:**
1. **Security group rules blocking**:
   ```bash
   # Check and fix
   ./scripts/verify-rds-security.sh
   ```

2. **Subnet group issues**:
   ```bash
   # Recreate subnet group
   terraform destroy -target=aws_db_subnet_group.mojaloop
   terraform apply -target=aws_db_subnet_group.mojaloop
   ```

---

## 🔧 Quick Diagnostic Commands

```bash
# Full infrastructure health check
./scripts/health-check.sh

# Common issues auto-fix
./scripts/auto-fix-common.sh

# Generate debug bundle for support
./scripts/create-debug-bundle.sh
```

## 📊 Performance Issues

### Slow Terraform Operations

**Speed up Terraform**:
```bash
# Enable parallelism
export TF_CLI_ARGS_apply="-parallelism=20"

# Use S3 backend for state
terraform init -backend-config=backend-s3.conf
```

### High AWS Costs During Testing

**Cost Optimization**:
```bash
# Use spot instances where possible
./scripts/enable-spot-instances.sh

# Scale down between tests
./scripts/scale-down.sh

# Schedule automatic shutdown
./scripts/schedule-shutdown.sh --after-hours
```

## 🚨 Emergency Procedures

### Complete Infrastructure Failure

```bash
# 1. Capture current state
./scripts/emergency-backup-state.sh

# 2. Force cleanup (if normal destroy fails)
./scripts/force-cleanup.sh --confirm

# 3. Start fresh
./deploy.sh --clean-start
```

### Rollback Infrastructure Changes

```bash
# Rollback to previous terraform state
./scripts/rollback-infrastructure.sh

# Or rollback to specific version
./scripts/rollback-infrastructure.sh --version=3
```

## 💡 Prevention Tips

1. **Always run pre-flight checks**:
   ```bash
   ./scripts/preflight-check.sh --comprehensive
   ```

2. **Use canary deployments**:
   ```bash
   ./deploy.sh --canary  # Creates 1 node first
   ```

3. **Monitor during deployment**:
   ```bash
   # In another terminal
   ./scripts/monitor-deployment.sh --alerts
   ```

## 🆘 Still Stuck?

1. **Collect diagnostics**:
   ```bash
   ./scripts/collect-diagnostics.sh > diagnostics.txt
   ```

2. **Check AWS Status**:
   - [AWS Service Health](https://status.aws.amazon.com/)
   - Regional issues: `aws health describe-events`

3. **Common fixes bundle**:
   ```bash
   curl -sL https://mojaloop.io/perf-test-fixes | bash
   ```

Remember: Most issues are transient AWS capacity problems. Try a different region or wait 30 minutes before major troubleshooting.