# Terraform Infrastructure for Mojaloop Performance Testing

## Overview
This Terraform module creates AWS infrastructure for Mojaloop performance testing with:
- VPC with public and private subnets
- Bastion host for secure access
- Switch nodes (control plane) - 3 nodes for HA
- DFSP nodes (workers) - 8 nodes by default
- Security groups with proper isolation
- NAT Gateway for outbound internet access from private subnet

## Architecture
```
Internet
    |
    v
[Internet Gateway]
    |
    v
[Public Subnet: 10.110.1.0/24]
    |
    +-- [Bastion Host] <-- SSH from Internet
    |
    +-- [NAT Gateway]
            |
            v
[Private Subnet: 10.110.2.0/24]
    |
    +-- [Switch Nodes: sw1-n1, sw1-n2, sw1-n3]
    |
    +-- [DFSP Nodes: fsp101-108]
```

## Prerequisites
1. AWS CLI configured with profile `gtmlab`
2. SSH key pair `ndelma-gtm-202504091000` exists in AWS
3. Terraform >= 1.0

## Configuration
All infrastructure is defined in `../config.yaml`. Key sections:
- `aws`: AWS profile and region
- `network`: VPC and subnet configuration
- `security`: Security group rules
- `vms`: Instance specifications

## Usage

### Initialize Terraform
```bash
cd terraform
terraform init
```

### Review Plan
```bash
terraform plan
```

### Apply Infrastructure
```bash
terraform apply
```

### Destroy Infrastructure
```bash
terraform destroy
```

## Outputs
After successful deployment:
- `bastion_public_ip`: Public IP to SSH to bastion
- `ssh_config_entry`: SSH config for ~/.ssh/config
- `ansible_inventory`: Generated Ansible inventory
- `inventory-generated.yaml`: Auto-generated inventory file

## SSH Access
1. Connect to bastion:
```bash
ssh -i ~/.ssh/ndelma-gtm-202504091000.pem ubuntu@<bastion_public_ip>
```

2. From bastion, connect to internal nodes:
```bash
ssh ubuntu@<private_ip>
```

Or use SSH ProxyJump:
```bash
ssh -J ubuntu@<bastion_public_ip> ubuntu@<private_ip>
```

## Security
- Only bastion has public IP
- Internal nodes accessible only through bastion
- All nodes have internet egress through NAT Gateway
- Security groups enforce strict ingress rules

## Customization
Copy `terraform.tfvars.example` to `terraform.tfvars` to override:
- AMI ID
- SSH allowed CIDR blocks
- Project name
- Region