# Security Group for Bastion Host
resource "aws_security_group" "bastion" {
  count = var.create_bastion && local.bastion_config.enabled ? 1 : 0

  name        = "${local.project_config.name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name    = "${local.project_config.name}-bastion-sg"
      Purpose = "Bastion SSH access"
    }
  )
}

# Bastion Security Group Rules - Ingress
resource "aws_security_group_rule" "bastion_ingress" {
  for_each = var.create_bastion && local.bastion_config.enabled ? {
    for idx, rule in local.security_config.bastion.ingress_rules : idx => rule
  } : {}

  type              = "ingress"
  from_port         = tonumber(split("-", tostring(each.value.port))[0])
  to_port           = contains(split("-", tostring(each.value.port)), "-") ? tonumber(split("-", tostring(each.value.port))[1]) : tonumber(split("-", tostring(each.value.port))[0])
  protocol          = each.value.protocol
  cidr_blocks       = coalesce(var.allowed_ssh_cidr_blocks, try(each.value.cidr_blocks, null))
  security_group_id = aws_security_group.bastion[0].id
  description       = each.value.description
}

# Bastion Security Group Rules - Egress
resource "aws_security_group_rule" "bastion_egress" {
  for_each = var.create_bastion && local.bastion_config.enabled ? {
    for idx, rule in local.security_config.bastion.egress_rules : idx => rule
  } : {}

  type              = "egress"
  from_port         = each.value.protocol == "-1" ? 0 : tonumber(split("-", tostring(each.value.port))[0])
  to_port           = each.value.protocol == "-1" ? 0 : (contains(split("-", tostring(each.value.port)), "-") ? tonumber(split("-", tostring(each.value.port))[1]) : tonumber(split("-", tostring(each.value.port))[0]))
  protocol          = each.value.protocol
  cidr_blocks       = each.value.cidr_blocks
  security_group_id = aws_security_group.bastion[0].id
  description       = each.value.description
}

# Security Group for Internal Nodes (Switch and DFSP)
resource "aws_security_group" "internal" {
  name        = "${local.project_config.name}-internal-sg"
  description = "Security group for internal cluster nodes"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name    = "${local.project_config.name}-internal-sg"
      Purpose = "Internal cluster communication"
    }
  )
}

# Internal Security Group Rules - Ingress
resource "aws_security_group_rule" "internal_ingress" {
  for_each = {
    for idx, rule in local.security_config.internal.ingress_rules : idx => rule
  }

  type              = "ingress"
  from_port         = each.value.protocol == "-1" ? 0 : tonumber(split("-", tostring(each.value.port))[0])
  to_port           = each.value.protocol == "-1" ? 0 : (contains(split("-", tostring(each.value.port)), "-") ? tonumber(split("-", tostring(each.value.port))[1]) : tonumber(split("-", tostring(each.value.port))[0]))
  protocol          = each.value.protocol
  cidr_blocks       = try(each.value.cidr_blocks, null)
  security_group_id = aws_security_group.internal.id
  description       = each.value.description

  # Handle source references
  source_security_group_id = (
    try(each.value.source, null) == "self" ? aws_security_group.internal.id :
    try(each.value.source, null) == "bastion_sg" && var.create_bastion && local.bastion_config.enabled ? aws_security_group.bastion[0].id :
    null
  )
}

# Internal Security Group Rules - Egress
resource "aws_security_group_rule" "internal_egress" {
  for_each = {
    for idx, rule in local.security_config.internal.egress_rules : idx => rule
  }

  type              = "egress"
  from_port         = each.value.protocol == "-1" ? 0 : tonumber(split("-", tostring(each.value.port))[0])
  to_port           = each.value.protocol == "-1" ? 0 : (contains(split("-", tostring(each.value.port)), "-") ? tonumber(split("-", tostring(each.value.port))[1]) : tonumber(split("-", tostring(each.value.port))[0]))
  protocol          = each.value.protocol
  cidr_blocks       = each.value.cidr_blocks
  security_group_id = aws_security_group.internal.id
  description       = each.value.description
}