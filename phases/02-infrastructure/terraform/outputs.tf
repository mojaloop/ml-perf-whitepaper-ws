# Network Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

# Bastion Outputs
output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].public_ip : null
}

output "bastion_private_ip" {
  description = "Private IP address of the bastion host"
  value       = var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].private_ip : null
}

output "bastion_instance_id" {
  description = "Instance ID of the bastion host"
  value       = var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].id : null
}

# Switch Node Outputs
output "switch_nodes" {
  description = "Map of switch node details"
  value = {
    for name, instance in aws_instance.switch : name => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      name        = name
    }
  }
}

# DFSP Node Outputs
output "dfsp_nodes" {
  description = "Map of DFSP node details"
  value = {
    for name, instance in aws_instance.dfsp : name => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      name        = name
    }
  }
}

# Security Group Outputs
output "bastion_security_group_id" {
  description = "ID of the bastion security group"
  value       = var.create_bastion && local.bastion_config.enabled ? aws_security_group.bastion[0].id : null
}

output "internal_security_group_id" {
  description = "ID of the internal nodes security group"
  value       = aws_security_group.internal.id
}

# SSH Connection Commands
output "ssh_bastion_command" {
  description = "SSH command to connect to bastion"
  value       = var.create_bastion && local.bastion_config.enabled ? "ssh -i ~/.ssh/${local.ssh_config.key_name}.pem ubuntu@${aws_instance.bastion[0].public_ip}" : null
}

output "ssh_config_file" {
  description = "Generated SSH config file location"
  value       = local_file.ssh_config.filename
}

# Generate Ansible Inventory
output "ansible_inventory" {
  description = "Ansible inventory content"
  value = templatefile("${path.module}/templates/inventory.yaml.tpl", {
    bastion_public_ip  = var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].public_ip : ""
    bastion_private_ip = var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].private_ip : ""
    bastion_instance_id = var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].id : ""
    switch_nodes = {
      for name, instance in aws_instance.switch : name => {
        private_ip  = instance.private_ip
        instance_id = instance.id
      }
    }
    dfsp_nodes = {
      for name, instance in aws_instance.dfsp : name => {
        private_ip  = instance.private_ip
        instance_id = instance.id
      }
    }
    project_name = local.project_config.name
    environment  = local.project_config.environment
    region       = local.aws_config.region
  })
}

# Write inventory to file
resource "local_file" "ansible_inventory" {
  content  = templatefile("${path.module}/templates/inventory.yaml.tpl", {
    bastion_public_ip  = var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].public_ip : ""
    bastion_private_ip = var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].private_ip : ""
    bastion_instance_id = var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].id : ""
    switch_nodes = {
      for name, instance in aws_instance.switch : name => {
        private_ip  = instance.private_ip
        instance_id = instance.id
      }
    }
    dfsp_nodes = {
      for name, instance in aws_instance.dfsp : name => {
        private_ip  = instance.private_ip
        instance_id = instance.id
      }
    }
    project_name = local.project_config.name
    environment  = local.project_config.environment
    region       = local.aws_config.region
  })
  filename = "${path.module}/../artifacts/inventory.yaml"

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../artifacts"
  }
}

# Write SSH config to file
resource "local_file" "ssh_config" {
  content = templatefile("${path.module}/templates/ssh_config.tpl", {
    bastion_public_ip = var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].public_ip : ""
    ssh_key_name     = local.ssh_config.key_name
    switch_nodes = {
      for name, instance in aws_instance.switch : name => {
        private_ip = instance.private_ip
      }
    }
    dfsp_nodes = {
      for name, instance in aws_instance.dfsp : name => {
        private_ip = instance.private_ip
      }
    }
  })
  filename = "${path.module}/../artifacts/ssh-config"

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../artifacts"
  }
}

# Generate hosts file for /etc/hosts
resource "local_file" "hosts_file" {
  content = <<-EOT
# Mojaloop Performance Testing Infrastructure Hosts
# Generated by Terraform at: ${timestamp()}
# Add to /etc/hosts or use with --hosts-file

# Bastion
${var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].public_ip : ""}    perf-jump-host bastion

# Switch Nodes
%{ for name, instance in aws_instance.switch ~}
${instance.private_ip}    ${name}
%{ endfor ~}

# DFSP Nodes
%{ for name, instance in aws_instance.dfsp ~}
${instance.private_ip}    ${name}
%{ endfor ~}
EOT
  filename = "${path.module}/../artifacts/hosts"

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../artifacts"
  }
}

# Generate connection instructions
resource "local_file" "connection_info" {
  content = <<-EOT
===============================================================================
Mojaloop Performance Testing Infrastructure - Connection Information
Generated: ${timestamp()}
===============================================================================

BASTION HOST:
  Public IP: ${var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].public_ip : "N/A"}
  SSH: ssh -i ~/.ssh/${local.ssh_config.key_name}.pem ubuntu@${var.create_bastion && local.bastion_config.enabled ? aws_instance.bastion[0].public_ip : "N/A"}

QUICK SETUP:
  1. Append SSH config to your local SSH config:
     cat artifacts/ssh-config >> ~/.ssh/config

  2. Test connection to bastion:
     ssh perf-jump-host

  3. Connect to any node:
     ssh sw1-n1
     ssh fsp101

FILES GENERATED:
  - artifacts/inventory.yaml     : Ansible inventory
  - artifacts/ssh-config        : SSH client configuration
  - artifacts/hosts             : Hosts file entries
  - artifacts/connection-info.txt : This file

SWITCH NODES:
%{ for name, instance in aws_instance.switch ~}
  ${name}: ${instance.private_ip}
%{ endfor ~}

DFSP NODES:
%{ for name, instance in aws_instance.dfsp ~}
  ${name}: ${instance.private_ip}
%{ endfor ~}
===============================================================================
EOT
  filename = "${path.module}/../artifacts/connection-info.txt"

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../artifacts"
  }
}