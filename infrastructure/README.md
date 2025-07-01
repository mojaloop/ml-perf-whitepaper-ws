# Infrastructure

This directory contains all infrastructure as code for provisioning the AWS environment needed for Mojaloop performance testing.

## Directory Structure

- **terraform/**: Terraform modules for AWS resources
- **aws/**: AWS-specific configurations and scripts
- **network-diagrams/**: Architecture and network topology diagrams

## Components

### AWS Resources

1. **VPC and Networking**
   - Multi-AZ VPC with public/private subnets
   - NAT gateways for outbound connectivity
   - VPC peering for K6 infrastructure isolation

2. **EKS Clusters**
   - Main Mojaloop cluster (c5.4xlarge nodes minimum)
   - Separate K6 testing cluster (t3.2xlarge nodes)
   - Auto-scaling groups for both clusters

3. **Storage**
   - EBS volumes for persistent storage
   - S3 buckets for result archival
   - EFS for shared test data

4. **Load Balancers**
   - ALB for external access
   - NLB for internal services

## Provisioning Steps

1. Configure AWS credentials
2. Customize terraform.tfvars
3. Run Terraform:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Sizing Guidelines

For 1000 TPS with 8 DFSPs:
- **Mojaloop Cluster**: 10-15 c5.4xlarge nodes
- **K6 Cluster**: 5-8 t3.2xlarge nodes
- **RDS**: db.r5.2xlarge for central ledger
- **ElastiCache**: cache.m5.xlarge for Redis

## Network Architecture

Document VPC design, security groups, and network flow between components.
