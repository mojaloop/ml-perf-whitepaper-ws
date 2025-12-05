# Optional override variables (can be set via terraform.tfvars or command line)

variable "config_file_path" {
  description = "Path to the configuration YAML file"
  type        = string
  default     = "../config.yaml"
}

variable "override_project_name" {
  description = "Override the project name from config.yaml"
  type        = string
  default     = null
}

variable "override_region" {
  description = "Override the AWS region from config.yaml"
  type        = string
  default     = null
}

variable "override_ami_id" {
  description = "Override the default AMI ID from config.yaml"
  type        = string
  default     = null
}

variable "create_bastion" {
  description = "Whether to create the bastion host"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidr_blocks" {
  description = "Override CIDR blocks allowed to SSH to bastion"
  type        = list(string)
  default     = null
}