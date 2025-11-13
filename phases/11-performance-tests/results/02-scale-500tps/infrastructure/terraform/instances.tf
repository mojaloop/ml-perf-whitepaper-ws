# Data source for SSH key
data "aws_key_pair" "existing" {
  key_name = local.ssh_config.key_name
}

# Bastion Instance
resource "aws_instance" "bastion" {
  count = var.create_bastion && local.bastion_config.enabled ? 1 : 0

  ami           = coalesce(var.override_ami_id, local.vms_config.default_ami)
  instance_type = local.bastion_config.instance_type
  key_name      = data.aws_key_pair.existing.key_name

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion[0].id]
  associate_public_ip_address = true
  monitoring                   = local.detailed_monitoring

  root_block_device {
    volume_size           = local.bastion_config.root_volume.size
    volume_type           = local.bastion_config.root_volume.type
    delete_on_termination = local.bastion_config.root_volume.delete_on_termination
    encrypted             = true

    tags = merge(
      local.common_tags,
      {
        Name = "${local.project_config.name}-${local.bastion_config.name}-root"
      }
    )
  }

  user_data = <<-EOF
    #!/bin/bash
    # Set hostname
    hostnamectl set-hostname ${local.bastion_config.name}
    echo "127.0.1.1 ${local.bastion_config.name}" >> /etc/hosts

    # Update system
    apt-get update
  EOF

  tags = merge(
    local.common_tags,
    local.bastion_config.tags,
    {
      Name = "${local.project_config.name}-${local.bastion_config.name}"
    }
  )

  lifecycle {
    prevent_destroy       = false
    create_before_destroy = false
    ignore_changes        = []
  }
}

# Switch Node Instances
resource "aws_instance" "switch" {
  for_each = {
    for instance in local.switch_instances : instance.name => instance
  }

  ami           = coalesce(var.override_ami_id, local.vms_config.default_ami)
  instance_type = try(each.value.instance_type, local.switch_defaults.instance_type)
  key_name      = data.aws_key_pair.existing.key_name

  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.internal.id]
  associate_public_ip_address = false

  # Performance optimizations
  placement_group = local.placement_group_enabled ? aws_placement_group.cluster[0].id : null
  monitoring      = local.detailed_monitoring
  ebs_optimized   = try(each.value.performance.ebs_optimized, local.switch_defaults.performance.ebs_optimized, true)

  root_block_device {
    volume_size = try(
      each.value.root_volume.size,
      local.switch_defaults.root_volume.size
    )
    volume_type = try(
      each.value.root_volume.type,
      local.switch_defaults.root_volume.type
    )
    iops = try(
      each.value.root_volume.iops,
      local.switch_defaults.root_volume.iops,
      null
    )
    # Only set throughput for gp3 volumes (not io2)
    throughput = try(
      each.value.root_volume.type,
      local.switch_defaults.root_volume.type
    ) == "gp3" ? try(
      each.value.root_volume.throughput,
      local.switch_defaults.root_volume.throughput,
      null
    ) : null
    delete_on_termination = try(
      each.value.root_volume.delete_on_termination,
      local.switch_defaults.root_volume.delete_on_termination
    )
    encrypted = true

    tags = merge(
      local.common_tags,
      {
        Name = "${local.project_config.name}-${each.value.name}-root"
      }
    )
  }

  user_data = <<-EOF
    #!/bin/bash
    # Set hostname
    hostnamectl set-hostname ${each.value.name}
    echo "127.0.1.1 ${each.value.name}" >> /etc/hosts

    # Disable swap for Kubernetes
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab

    # Update system
    apt-get update

    # Install basic tools
    apt-get install -y curl wget git vim net-tools

    # Configure kernel modules for Kubernetes
    cat <<-EOT >> /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    EOT

    modprobe overlay
    modprobe br_netfilter

    # Configure sysctl for Kubernetes networking
    cat <<-EOT >> /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    EOT

    sysctl --system
  EOF

  tags = merge(
    local.common_tags,
    each.value.tags,
    {
      Name = "${local.project_config.name}-${each.value.name}"
    }
  )

  lifecycle {
    prevent_destroy       = false
    create_before_destroy = false
    ignore_changes        = []
  }
}

# DFSP Node Instances
resource "aws_instance" "dfsp" {
  for_each = {
    for instance in local.dfsp_instances : instance.name => instance
  }

  ami           = coalesce(var.override_ami_id, local.vms_config.default_ami)
  instance_type = try(each.value.instance_type, local.dfsp_defaults.instance_type)
  key_name      = data.aws_key_pair.existing.key_name

  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.internal.id]
  associate_public_ip_address = false

  # Performance optimizations
  placement_group = local.placement_group_enabled ? aws_placement_group.cluster[0].id : null
  monitoring      = local.detailed_monitoring

  root_block_device {
    volume_size = try(
      each.value.root_volume.size,
      local.dfsp_defaults.root_volume.size
    )
    volume_type = try(
      each.value.root_volume.type,
      local.dfsp_defaults.root_volume.type
    )
    iops = try(
      each.value.root_volume.iops,
      local.dfsp_defaults.root_volume.iops,
      null
    )
    throughput = try(
      each.value.root_volume.throughput,
      local.dfsp_defaults.root_volume.throughput,
      null
    )
    delete_on_termination = try(
      each.value.root_volume.delete_on_termination,
      local.dfsp_defaults.root_volume.delete_on_termination
    )
    encrypted = true

    tags = merge(
      local.common_tags,
      {
        Name = "${local.project_config.name}-${each.value.name}-root"
      }
    )
  }

  user_data = <<-EOF
    #!/bin/bash
    # Set hostname
    hostnamectl set-hostname ${each.value.name}
    echo "127.0.1.1 ${each.value.name}" >> /etc/hosts

    # Disable swap for Kubernetes
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab

    # Update system
    apt-get update

    # Install basic tools
    apt-get install -y curl wget git vim net-tools

    # Configure kernel modules for Kubernetes
    cat <<-EOT >> /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    EOT

    modprobe overlay
    modprobe br_netfilter

    # Configure sysctl for Kubernetes networking
    cat <<-EOT >> /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    EOT

    sysctl --system
  EOF

  tags = merge(
    local.common_tags,
    each.value.tags,
    {
      Name = "${local.project_config.name}-${each.value.name}"
    }
  )

  lifecycle {
    prevent_destroy       = false
    create_before_destroy = false
    ignore_changes        = []
  }
}