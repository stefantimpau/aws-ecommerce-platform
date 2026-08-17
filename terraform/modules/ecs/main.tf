data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)

  task_role_arns = {
    product = var.product_task_role_arn
    cart    = var.cart_task_role_arn
    user    = var.user_task_role_arn
    order   = var.order_task_role_arn
  }

  # Per-service environment variables. Everything here is non-secret config
  # already created by the rds/ssm-config modules — actual secrets (the DB
  # password) go through the `secrets` block below instead, never here.
  service_environment = {
    product = {
      PORT                = tostring(var.container_ports["product"])
      AWS_REGION          = var.aws_region
      PRODUCTS_TABLE_NAME = var.dynamodb_products_table
    }
    cart = {
      PORT            = tostring(var.container_ports["cart"])
      AWS_REGION      = var.aws_region
      CART_TABLE_NAME = var.dynamodb_cart_table
    }
    user = {
      PORT                 = tostring(var.container_ports["user"])
      AWS_REGION           = var.aws_region
      COGNITO_USER_POOL_ID = var.cognito_user_pool_id
    }
    order = {
      PORT                   = tostring(var.container_ports["order"])
      AWS_REGION             = var.aws_region
      DB_HOST                = var.db_host
      DB_PORT                = tostring(var.db_port)
      DB_NAME                = var.db_name
      DB_USERNAME            = var.db_username
      ORDER_EVENTS_TOPIC_ARN = var.order_events_topic_arn
    }
  }

  # Only the order service talks to RDS, so it's the only one that needs
  # the DB password secret injected.
  service_secrets = {
    product = []
    cart    = []
    user    = []
    order = [
      { name = "DB_PASSWORD", valueFrom = var.db_password_ssm_param_arn }
    ]
  }
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-cluster"
  })
}

# One log group per service, matching the /ecs/<project>-<environment>/*
# pattern the IAM execution role's CloudWatch Logs permission is scoped to
# (terraform/modules/iam local.log_group_arn_pattern) — keep these in sync.
resource "aws_cloudwatch_log_group" "this" {
  for_each = var.container_ports

  name              = "/ecs/${local.name}/${each.key}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name    = "/ecs/${local.name}/${each.key}"
    Service = each.key
  })
}

resource "aws_ecs_task_definition" "this" {
  for_each = var.container_ports

  family                   = "${local.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = local.task_role_arns[each.key]

  container_definitions = jsonencode([
    {
      name      = "${each.key}-service"
      image     = "${var.ecr_repository_urls[each.key]}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = each.value
          protocol      = "tcp"
        }
      ]

      environment = [
        for k, v in local.service_environment[each.key] : { name = k, value = v }
      ]

      secrets = local.service_secrets[each.key]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = each.key
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:${each.value}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name    = "${local.name}-${each.key}"
    Service = each.key
  })
}

# ---------------------------------------------------------------------------
# ECS services — build order step 10: launched here WITHOUT a load balancer
# attached (attach_load_balancer defaults to false), so this can go live
# and be verified (tasks start, reach RDS/DynamoDB) independent of the
# internal ALB. Step 15 flips attach_load_balancer to true once the ALB
# and target groups exist — Terraform updates the existing services in
# place rather than recreating them.
#
# No public IP: tasks live in the private-app subnets and reach the
# internet (ECR pulls, DynamoDB/SSM/Cognito API calls) via the NAT
# Gateway from the vpc module.
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "this" {
  for_each = var.container_ports

  name            = "${local.name}-${each.key}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.ecs_tasks_sg_id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.attach_load_balancer ? [1] : []
    content {
      target_group_arn = var.target_group_arns[each.key]
      container_name   = "${each.key}-service"
      container_port   = each.value
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name}-${each.key}"
    Service = each.key
  })

  depends_on = [aws_cloudwatch_log_group.this]
}
