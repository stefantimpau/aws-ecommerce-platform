locals {
  name = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)

  # ALB and target group `name` arguments are capped by AWS at 32
  # characters — local.name alone (e.g. "aws-ecommerce-platform-dev") is
  # already too long once any suffix is added. Build a short, still
  # derived-from-the-project prefix instead of hardcoding one: first 4
  # characters of the project name (minus the "aws-" prefix) + environment,
  # e.g. "ecom-dev". Full names stay on the `Name` tag for readability.
  short_name = "${substr(replace(var.project, "aws-", ""), 0, 4)}-${var.environment}"

  # Deterministic listener rule priorities (100, 110, 120, ...) derived from
  # sorted service names, rather than hand-assigned numbers that could drift
  # out of sync as services are added.
  service_names = sort(keys(var.container_ports))
  rule_priority = {
    for idx, svc in local.service_names : svc => 100 + (idx * 10)
  }
}

# ---------------------------------------------------------------------------
# Internal Application Load Balancer — sits behind the API Gateway VPC Link
# (build step 16), never internet-facing. Lives in the private-app subnets
# and is only reachable from within the VPC (see the alb security group's
# ingress rule, scoped to the VPC CIDR).
#
# This was the resource blocked by the account-level LB restriction noted
# in the README's Incident Notes — created now that the restriction has
# been lifted, picking up build order step 14.
# ---------------------------------------------------------------------------

resource "aws_lb" "internal" {
  name               = "${local.short_name}-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  # Portfolio project torn down within days of demoing — deletion
  # protection would just add a manual step to the teardown script for no
  # real benefit here.
  enable_deletion_protection = false

  tags = merge(local.common_tags, {
    Name = "${local.name}-internal-alb"
  })
}

# ---------------------------------------------------------------------------
# One target group per service — target_type "ip" because Fargate awsvpc
# tasks register by ENI IP, not instance ID. Health checks hit each
# container's /health endpoint (same path the ECS task definition's own
# container healthCheck already probes).
# ---------------------------------------------------------------------------

resource "aws_lb_target_group" "this" {
  for_each = var.container_ports

  name        = "${local.short_name}-${each.key}-tg"
  port        = each.value
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name}-${each.key}-tg"
    Service = each.key
  })
}

# ---------------------------------------------------------------------------
# Single HTTP listener on port 80 (internal-only traffic behind the VPC
# Link — no TLS needed on this hop; TLS terminates at API Gateway's custom
# domain in build step 19). Default action is a plain 404 so unmatched
# paths fail closed instead of silently hitting one service.
# ---------------------------------------------------------------------------

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = local.common_tags
}

resource "aws_lb_listener_rule" "this" {
  for_each = var.container_ports

  listener_arn = aws_lb_listener.http.arn
  priority     = local.rule_priority[each.key]

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  condition {
    path_pattern {
      values = var.path_patterns[each.key]
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name}-${each.key}-rule"
    Service = each.key
  })
}

# ---------------------------------------------------------------------------
# WAF association — build step 20. This ALB, not the API Gateway HTTP API
# in front of it, is the actual attach point for the API's Web ACL — AWS
# WAF doesn't support HTTP APIs (see terraform/modules/apigateway/main.tf's
# comment for the full story). ALB is a supported target regardless of
# internal/internet-facing, and every request that reaches this ALB has
# already passed through API Gateway + the VPC Link, so inspection here
# covers the same traffic, just one hop later.
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl_association" "this" {
  count        = var.attach_web_acl ? 1 : 0
  resource_arn = aws_lb.internal.arn
  web_acl_arn  = var.web_acl_arn
}
