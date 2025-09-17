
# Deployment guide

## Create infra

### Networking

```bash
# Set region
export AWS_REGION=eu-west-2 

# Set project name for consistent tagging
export PROJECT_NAME=perf-test-202507311044

# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --region $AWS_REGION \
  --cidr-block 10.110.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc},{Key=Project,Value=${PROJECT_NAME}},{Key=Environment,Value=dev}]" \
  --query 'Vpc.VpcId' \
  --output text\
  --profile gtmlab)
# vpc-05aeb0446c0d339b0

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
  --region $AWS_REGION \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames \
  --profile gtmlab

# Create public subnet
SUBNET_ID=$(aws ec2 create-subnet \
  --region $AWS_REGION \
  --vpc-id $VPC_ID \
  --cidr-block 10.110.1.0/24 \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-subnet},{Key=Project,Value=${PROJECT_NAME}},{Key=Type,Value=public}]" \
  --query 'Subnet.SubnetId' \
  --output text \
  --profile gtmlab)

# Create internet gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $AWS_REGION \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text \
  --profile gtmlab)

# Attach gateway to VPC
aws ec2 attach-internet-gateway \
  --region $AWS_REGION \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID \
  --profile gtmlab

# Get main route table ID
RTB_ID=$(aws ec2 describe-route-tables \
  --region $AWS_REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
  --query 'RouteTables[0].RouteTableId' \
  --output text \
  --profile gtmlab)

# Tag the main route table
aws ec2 create-tags \
  --region $AWS_REGION \
  --resources $RTB_ID \
  --tags "Key=Name,Value=${PROJECT_NAME}-main-rtb" "Key=Project,Value=${PROJECT_NAME}" \
  --profile gtmlab

# Add route to internet gateway
aws ec2 create-route \
  --region $AWS_REGION \
  --route-table-id $RTB_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --profile gtmlab
```

### Security groups

```bash
# Create security group
SG_ID=$(aws ec2 create-security-group \
  --region $AWS_REGION \
  --group-name ${PROJECT_NAME}-sg \
  --description "Security group for MicroK8s cluster" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-sg},{Key=Project,Value=${PROJECT_NAME}},{Key=Purpose,Value=microk8s-cluster}]" \
  --query 'GroupId' \
  --output text \
  --profile gtmlab)

# SSH access
aws ec2 authorize-security-group-ingress \
  --region $AWS_REGION \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=SSH},{Key=Project,Value=${PROJECT_NAME}}]" \
  --profile gtmlab

# MicroK8s API server
aws ec2 authorize-security-group-ingress \
  --region $AWS_REGION \
  --group-id $SG_ID \
  --protocol tcp \
  --port 16443 \
  --cidr 0.0.0.0/0 \
  --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=MicroK8s-API},{Key=Project,Value=${PROJECT_NAME}}]" \
  --profile gtmlab

# MicroK8s clustering port
aws ec2 authorize-security-group-ingress \
  --region $AWS_REGION \
  --group-id $SG_ID \
  --protocol tcp \
  --port 25000 \
  --source-group $SG_ID \
  --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=MicroK8s-Cluster},{Key=Project,Value=${PROJECT_NAME}}]" \
  --profile gtmlab

# VXLAN for pod networking
aws ec2 authorize-security-group-ingress \
  --region $AWS_REGION \
  --group-id $SG_ID \
  --protocol udp \
  --port 4789 \
  --source-group $SG_ID \
  --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=VXLAN},{Key=Project,Value=${PROJECT_NAME}}]" \
  --profile gtmlab

# Kubernetes NodePort range
aws ec2 authorize-security-group-ingress \
  --region $AWS_REGION \
  --group-id $SG_ID \
  --protocol tcp \
  --port 30000-32767 \
  --cidr 0.0.0.0/0 \
  --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=NodePort-Range},{Key=Project,Value=${PROJECT_NAME}}]" \
  --profile gtmlab

# Calico BGP
aws ec2 authorize-security-group-ingress \
  --region $AWS_REGION \
  --group-id $SG_ID \
  --protocol tcp \
  --port 179 \
  --source-group $SG_ID \
  --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=Calico-BGP},{Key=Project,Value=${PROJECT_NAME}}]" \
  --profile gtmlab

# etcd ports
aws ec2 authorize-security-group-ingress \
  --region $AWS_REGION \
  --group-id $SG_ID \
  --protocol tcp \
  --port 12379-12380 \
  --source-group $SG_ID \
  --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=etcd},{Key=Project,Value=${PROJECT_NAME}}]" \
  --profile gtmlab

# Allow all traffic between nodes
aws ec2 authorize-security-group-ingress \
  --region $AWS_REGION \
  --group-id $SG_ID \
  --protocol all \
  --source-group $SG_ID \
  --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=Internal-All},{Key=Project,Value=${PROJECT_NAME}}]" \
  --profile gtmlab

```

### VMs

```bash
#aws ec2 describe-key-pairs --profile gtmlab
SSH_KEY_NAME=ndelma-gtm-202504091000

# Get Ubuntu 24.04 AMI ID
# AMI_ID=$(aws ec2 describe-images \
#   --region $AWS_REGION \
#   --filters \
#     "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-lts-amd64-server-*" \
#     "Name=state,Values=available" \
#   --query 'Images[0].ImageId' \
#   --output text \
#   --profile gtmlab)
# ami-044415bb13eee2391  <-- LTS
export AMI_ID=ami-044415bb13eee2391

# Launch node sw-001
INSTANCE_0=$(aws ec2 run-instances \
  --region $AWS_REGION \
  --image-id $AMI_ID \
  --instance-type m4.2xlarge \
  --key-name ${SSH_KEY_NAME} \
  --security-group-ids $SG_ID \
  --subnet-id $SUBNET_ID \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-sw-001},{Key=Project,Value=${PROJECT_NAME}},{Key=Role,Value=ml-sw},{Key=NodeNumber,Value=1}]" \
                      "ResourceType=volume,Tags=[{Key=Name,Value=${PROJECT_NAME}-sw-001},{Key=Project,Value=${PROJECT_NAME}}]" \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=64,VolumeType=gp3,DeleteOnTermination=true}' \
  --query 'Instances[0].InstanceId' \
  --output text \
  --profile gtmlab)

# Launch node dfsp-101
INSTANCE_1=$(aws ec2 run-instances \
  --region $AWS_REGION \
  --image-id $AMI_ID \
  --instance-type m4.xlarge \
  --key-name ${SSH_KEY_NAME} \
  --security-group-ids $SG_ID \
  --subnet-id $SUBNET_ID \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-dfsp-101},{Key=Project,Value=${PROJECT_NAME}},{Key=Role,Value=ml-dfsp},{Key=NodeNumber,Value=101}]" \
                      "ResourceType=volume,Tags=[{Key=Name,Value=${PROJECT_NAME}-dfsp-101},{Key=Project,Value=${PROJECT_NAME}}]" \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=64,VolumeType=gp3,DeleteOnTermination=true}' \
  --query 'Instances[0].InstanceId' \
  --output text \
  --profile gtmlab)

# Launch node dfsp-102
INSTANCE_2=$(aws ec2 run-instances \
  --region $AWS_REGION \
  --image-id $AMI_ID \
  --instance-type m4.xlarge \
  --key-name ${SSH_KEY_NAME} \
  --security-group-ids $SG_ID \
  --subnet-id $SUBNET_ID \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-dfsp-102},{Key=Project,Value=${PROJECT_NAME}},{Key=Role,Value=ml-dfsp},{Key=NodeNumber,Value=101}]" \
                      "ResourceType=volume,Tags=[{Key=Name,Value=${PROJECT_NAME}-dfsp-101},{Key=Project,Value=${PROJECT_NAME}}]" \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=64,VolumeType=gp3,DeleteOnTermination=true}' \
  --query 'Instances[0].InstanceId' \
  --output text \
  --profile gtmlab)




### test only
# Launch node dfsp-202
INSTANCE_2=$(aws ec2 run-instances \
  --region $AWS_REGION \
  --image-id $AMI_ID \
  --instance-type m4.xlarge \
  --key-name ${SSH_KEY_NAME} \
  --security-group-ids $SG_ID \
  --subnet-id $SUBNET_ID \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-dfsp-202},{Key=Project,Value=${PROJECT_NAME}},{Key=Role,Value=ml-dfsp},{Key=NodeNumber,Value=202}]" \
                      "ResourceType=volume,Tags=[{Key=Name,Value=${PROJECT_NAME}-dfsp-202},{Key=Project,Value=${PROJECT_NAME}}]" \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=64,VolumeType=gp3,DeleteOnTermination=true}' \
  --query 'Instances[0].InstanceId' \
  --output text \
  --profile gtmlab)

```





## retreive some parameters
```bash
  export AWS_REGION=eu-west-2

  # Set project name (from your infrastructure)
  export PROJECT_NAME=perf-test-202507311044

  # Set SSH key name and AMI ID (from the infrastructure file)
  export SSH_KEY_NAME=ndelma-gtm-202504091000
  export AMI_ID=ami-044415bb13eee2391

  # Retrieve VPC ID by querying the existing VPC
  export VPC_ID=$(aws ec2 describe-vpcs \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=${PROJECT_NAME}-vpc" \
    --query 'Vpcs[0].VpcId' \
    --output text \
    --profile gtmlab)

  # Retrieve Subnet ID
  export SUBNET_ID=$(aws ec2 describe-subnets \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=${PROJECT_NAME}-public-subnet" \
    --query 'Subnets[0].SubnetId' \
    --output text \
    --profile gtmlab)

  # Retrieve Security Group ID
  export SG_ID=$(aws ec2 describe-security-groups \
    --region $AWS_REGION \
    --filters "Name=group-name,Values=${PROJECT_NAME}-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --profile gtmlab)

  # Verify the variables are set correctly
  echo "VPC_ID: $VPC_ID"
  echo "SUBNET_ID: $SUBNET_ID"
  echo "SG_ID: $SG_ID"
```