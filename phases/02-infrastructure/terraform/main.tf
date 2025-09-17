terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration - store state in artifacts folder
  backend "local" {
    path = "../artifacts/terraform.tfstate"
  }
}

# Load configuration from YAML file
locals {
  config_file = yamldecode(file("${path.module}/../config.yaml"))

  # Extract configuration sections
  aws_config      = local.config_file.aws
  project_config  = local.config_file.project
  ssh_config      = local.config_file.ssh
  network_config  = local.config_file.network
  security_config = local.config_file.security
  vms_config      = local.config_file.vms

  # Common tags for all resources
  common_tags = {
    Project     = local.project_config.name
    Environment = local.project_config.environment
    ManagedBy   = "Terraform"
    CreatedAt   = timestamp()
  }

  # Parse VM configurations
  bastion_config = local.vms_config.bastion
  switch_instances = local.vms_config.switch.instances
  dfsp_instances = local.vms_config.dfsps.instances
  dfsp_defaults = local.vms_config.dfsps.defaults
}

# Configure AWS Provider
provider "aws" {
  region  = local.aws_config.region
  profile = local.aws_config.profile

  default_tags {
    tags = local.common_tags
  }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}