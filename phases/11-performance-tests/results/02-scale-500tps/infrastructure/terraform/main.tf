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
  k8s_config      = local.config_file.k8s
  lb_config       = try(local.config_file.load_balancers, {})

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
  switch_defaults = local.vms_config.switch.defaults
  dfsp_instances = local.vms_config.dfsps.instances
  dfsp_defaults = local.vms_config.dfsps.defaults

  # Performance settings
  placement_group_enabled = try(local.aws_config.placement_group.enabled, false)
  detailed_monitoring = try(local.aws_config.cloudwatch.detailed_monitoring, false)

  # Load balancer settings
  nlb_config = try(local.lb_config.switch_nlb, null)
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

# Placement Group for all instances (performance optimization)
resource "aws_placement_group" "cluster" {
  count = local.placement_group_enabled ? 1 : 0

  name     = "${local.project_config.name}-cluster-pg"
  strategy = "cluster"  # All instances in same physical rack for lowest latency

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-cluster-pg"
      Purpose = "High-performance cluster placement"
    }
  )
}