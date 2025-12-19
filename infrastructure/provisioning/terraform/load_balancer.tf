# Network Load Balancer for Switch Cluster

# NLB for switch cluster (works with single AZ)
resource "aws_lb" "switch_nlb" {
  count = local.nlb_config != null && local.nlb_config.enabled ? 1 : 0

  name               = "${local.project_config.name}-switch-nlb"
  internal           = local.nlb_config.scheme == "internal"
  load_balancer_type = local.nlb_config.type
  subnets            = [aws_subnet.private.id]  # NLB works with single subnet/AZ

  enable_deletion_protection = false
  enable_cross_zone_load_balancing = false  # Keep false for best performance in single AZ

  tags = merge(
    local.common_tags,
    local.nlb_config.tags,
    {
      Name = "${local.project_config.name}-switch-nlb"
    }
  )
}

# Target group for port 80 traffic
resource "aws_lb_target_group" "switch_tcp_80" {
  count = local.nlb_config != null && local.nlb_config.enabled ? 1 : 0

  name     = "${local.project_config.name}-tcp-80"
  port     = local.nlb_config.listeners[0].target_port
  protocol = local.nlb_config.listeners[0].protocol
  vpc_id   = aws_vpc.main.id
  target_type = local.nlb_config.target_type

  health_check {
    enabled             = true
    healthy_threshold   = local.nlb_config.health_check.healthy_threshold
    unhealthy_threshold = local.nlb_config.health_check.unhealthy_threshold
    interval            = local.nlb_config.health_check.interval
    port                = local.nlb_config.health_check.port
    protocol            = local.nlb_config.health_check.protocol
  }

  deregistration_delay = 30  # Faster deregistration for NLB

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-tcp-80-tg"
    }
  )
}

# Target group for port 443 traffic
resource "aws_lb_target_group" "switch_tcp_443" {
  count = local.nlb_config != null && local.nlb_config.enabled && length(local.nlb_config.listeners) > 1 ? 1 : 0

  name     = "${local.project_config.name}-tcp-443"
  port     = local.nlb_config.listeners[1].target_port
  protocol = local.nlb_config.listeners[1].protocol
  vpc_id   = aws_vpc.main.id
  target_type = local.nlb_config.target_type

  health_check {
    enabled             = true
    healthy_threshold   = local.nlb_config.health_check.healthy_threshold
    unhealthy_threshold = local.nlb_config.health_check.unhealthy_threshold
    interval            = local.nlb_config.health_check.interval
    port                = local.nlb_config.health_check.port
    protocol            = local.nlb_config.health_check.protocol
  }

  deregistration_delay = 30  # Faster deregistration for NLB

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-tcp-443-tg"
    }
  )
}

# TCP Listener for port 80
resource "aws_lb_listener" "switch_tcp_80" {
  count = local.nlb_config != null && local.nlb_config.enabled ? 1 : 0

  load_balancer_arn = aws_lb.switch_nlb[0].arn
  port              = local.nlb_config.listeners[0].port
  protocol          = local.nlb_config.listeners[0].protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.switch_tcp_80[0].arn
  }
}

# TCP Listener for port 443
resource "aws_lb_listener" "switch_tcp_443" {
  count = local.nlb_config != null && local.nlb_config.enabled && length(local.nlb_config.listeners) > 1 ? 1 : 0

  load_balancer_arn = aws_lb.switch_nlb[0].arn
  port              = local.nlb_config.listeners[1].port
  protocol          = local.nlb_config.listeners[1].protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.switch_tcp_443[0].arn
  }
}

# Target group attachments for generic switch nodes only (port 80)
resource "aws_lb_target_group_attachment" "switch_tcp_80" {
  for_each = {
    for instance in local.switch_instances : instance.name => instance
    if lookup(instance.k8s.node_labels, "node-role", "") == "generic"
  }

  target_group_arn = aws_lb_target_group.switch_tcp_80[0].arn
  target_id        = aws_instance.switch[each.key].id
  port             = local.nlb_config.listeners[0].target_port
}

# Target group attachments for generic switch nodes only (port 443)
resource "aws_lb_target_group_attachment" "switch_tcp_443" {
  for_each = {
    for instance in local.switch_instances : instance.name => instance
    if (local.nlb_config != null &&
        local.nlb_config.enabled &&
        length(local.nlb_config.listeners) > 1 &&
        lookup(instance.k8s.node_labels, "node-role", "") == "generic")
  }

  target_group_arn = aws_lb_target_group.switch_tcp_443[0].arn
  target_id        = aws_instance.switch[each.key].id
  port             = local.nlb_config.listeners[1].target_port
}

# Security group rule to allow traffic from NLB
# Note: NLB preserves source IPs, so we need to allow traffic from anywhere within the VPC
resource "aws_security_group_rule" "internal_from_vpc_for_nlb" {
  count = local.nlb_config != null && local.nlb_config.enabled ? 1 : 0

  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = [local.network_config.vpc.cidr]
  security_group_id = aws_security_group.internal.id
  description       = "NodePort range from NLB (preserves source IP)"
}