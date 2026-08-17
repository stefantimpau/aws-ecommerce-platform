locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# Web tier — the internal ALB's security group. Created now even though the
# ALB itself can't be created yet (account-level LB restriction, see
# docs/adr and blockers notes) — the SG is a free-standing resource and
# gets attached to the ALB in Phase 2 (build order step 14).
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name_prefix = "${local.name}-alb-"
  description = "Internal ALB behind API Gateway VPC Link - accepts HTTP from the VPC Link ENIs only"
  vpc_id      = var.vpc_id

  # Ingress is scoped to the vpc_link security group specifically (build
  # step 16), not the whole VPC CIDR — only the API Gateway VPC Link's
  # ENIs should ever be able to reach this ALB.
  egress {
    description = "To ECS tasks on their container ports"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-alb-sg"
    Tier = "web"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# API Gateway VPC Link — the ENIs API Gateway creates in the private-app
# subnets to reach the internal ALB (build step 16). No ingress rule: the
# VPC Link only ever initiates outbound connections to the ALB, it never
# receives inbound traffic directly.
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpc_link" {
  name_prefix = "${local.name}-vpc-link-"
  description = "API Gateway VPC Link ENIs - outbound to the internal ALB only"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTP to the internal ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpc-link-sg"
    Tier = "web"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "alb_ingress_from_vpc_link" {
  security_group_id       = aws_security_group.alb.id
  type                     = "ingress"
  description              = "HTTP from the API Gateway VPC Link ENIs"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_link.id
}

# ---------------------------------------------------------------------------
# App tier — ECS Fargate task security group. Only accepts traffic from the
# ALB SG, on each service's container port.
# ---------------------------------------------------------------------------

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${local.name}-ecs-tasks-"
  description = "ECS Fargate tasks (Product/Cart/User/Order services) - accepts traffic from the internal ALB only"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound (ECR pulls, DynamoDB/RDS, SSM, SNS/SQS via VPC endpoints or NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-ecs-tasks-sg"
    Tier = "app"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ecs_tasks_ingress_from_alb" {
  for_each = var.container_ports

  security_group_id       = aws_security_group.ecs_tasks.id
  type                     = "ingress"
  description              = "${each.key} service port from the internal ALB"
  from_port                = each.value
  to_port                  = each.value
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

# ---------------------------------------------------------------------------
# Data tier — RDS Postgres security group. Only accepts traffic from the
# ECS tasks SG, on the Postgres port. Nothing else, including the ALB, can
# reach it directly.
# ---------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name_prefix = "${local.name}-rds-"
  description = "RDS Postgres (orders) - accepts traffic from ECS tasks only"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name}-rds-sg"
    Tier = "data"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rds_ingress_from_ecs" {
  security_group_id       = aws_security_group.rds.id
  type                     = "ingress"
  description              = "Postgres from ECS tasks"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
}

# RDS has no egress rules — it never needs to initiate outbound connections.
# (No default egress rule is created since we didn't declare an `egress`
# block above; AWS security groups deny all egress unless a rule allows it,
# except the *default* SG on a VPC which allows all egress. This is an
# explicit non-default SG, so it starts fully closed on egress by design.)
