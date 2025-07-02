# Phase 01: Prerequisites & Planning

> **Purpose**: Ensure you have everything needed
> 
> **Time Required**: 30 minutes
> 
> **Outcome**: Set base to proceed with confidence

## 🎯 Quick Check

If you can run these commands successfully, skip to [Requesting AWS Limits](#requesting-aws-limits):

```bash
# All should return version numbers
kubectl version --client
helm version
```

## 📋 What You'll Do

1. **Install Tools** - Get your local environment ready
2. **Estimate Costs** - Understand the financial commitment
3. **Final Validation** - Confirm everything is ready

## 🚀 Let's Start

### Step 1: Install Required Tools

<details>
<summary><strong>🍎 macOS Installation</strong></summary>

```bash
# Using Homebrew (install from https://brew.sh if needed)
brew install awscli kubectl helm jq

# Verify versions
./verify-tools.sh
```

</details>

<details>
<summary><strong>🐧 Linux Installation</strong></summary>

```bash
# Run our installer script
./install-tools-linux.sh

# Or manually install each tool - see MANUAL_INSTALL.md
```

</details>

<details>
<summary><strong>🪟 Windows (WSL2) Installation</strong></summary>

```bash
# Inside WSL2 Ubuntu
./install-tools-linux.sh

# Note: Native Windows is not supported
```

</details>

### Step 2: Understand the Costs

<details>
<summary><strong>💰 Detailed Cost Breakdown</strong></summary>

NOTE: Rought estimates, update, modify as needed

| Component | Hourly Cost | Daily Cost | Purpose |
|-----------|------------|------------|----------|
| Mojaloop EKS Cluster | $6.40 | $153.60 | 10x c5.4xlarge |
| K6 EKS Cluster | $2.56 | $61.44 | 8x t3.2xlarge |
| RDS (MySQL) | $0.68 | $16.32 | Central Ledger DB |
| ElastiCache | $0.34 | $8.16 | Redis for ALS |
| Load Balancers | $0.50 | $12.00 | ALB + NLB |
| Data Transfer | ~$1.00 | ~$24.00 | Varies with testing |
| **Total** | **~$11.48** | **~$275.52** | *Minimum* |

**With 1000 TPS testing**: Expect $400-500/day due to increased data transfer

</details>

### Step 3: Final Validation

Prerequisites Check
==================
✅ AWS CLI: Authenticated as user@example.com
✅ AWS Limits: All limits sufficient  
✅ Terraform: Version 1.5.7
✅ Kubectl: Version 1.28.2
✅ Helm: Version 3.12.3

🎉 All prerequisites met! Ready to proceed.

Next step: cd ../02-infrastructure && ./deploy.sh


## ❓ Common Questions

<details>
<summary><strong>What would be the AWS testing costs?</strong></summary>

Budget for $400-500/day during testing.

</details>


## ✅ Completion Checklist

Before moving to Phase 02:

- [ ] AWS credentials working
- [ ] All tools installed and correct versions

## 🚀 Next Step

**AWS Limits Ready?** → [Phase 02: Infrastructure](../02-infrastructure/)

**Waiting for Limit Increases?** → Set a reminder and read:
- [Architecture Overview](../../docs/architecture/overview.md)
- [Why Isolated K6 Infrastructure?](../../docs/architecture/k6-isolation.md)

