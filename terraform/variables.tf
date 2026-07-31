# Required: name of the AWS key-pair to attach to all EC2 instances.
# Set via TF_VAR_ssh_key_name (the Makefile derives this from SSH_KEY_NAME
# in the root .env). The matching private key must live at
# ~/.ssh/${ssh_key_name}.pem with mode 0600 — both the emitted ssh_config
# and ansible's ANSIBLE_PRIVATE_KEY_FILE point there.
variable "ssh_key_name" {
  description = "AWS key-pair name (must already exist in the AWS account)"
  type        = string
}

# Optional override variables (can be set via terraform.tfvars or command line)

variable "config_file_path" {
  description = "Path to the configuration YAML file. Set by Makefile via TF_VAR_config_file_path: scenario override if present, else common/aws.yaml."
  type        = string
  default     = "../common/aws.yaml"
}

variable "artifacts_dir" {
  description = "Directory for generated artifacts. Set by Makefile via TF_VAR_artifacts_dir to ../scenarios/<scenario>/artifacts."
  type        = string
  default     = "../scenarios/base/artifacts"
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