locals {
  name = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)

  # ECR repos and CloudWatch log groups don't exist yet (build steps 8 and
  # 9) but both follow a fixed naming convention this project controls, so
  # the execution role can be scoped to that naming prefix now rather than
  # waiting — still least-privilege (limited to this project's resources
  # only), just not limited to exact ARNs that don't exist yet.
  ecr_repo_arn_pattern  = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${local.name}-*"
  log_group_arn_pattern = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${local.name}/*"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# ECS task EXECUTION role — used by the ECS agent itself, not application
# code: pulls container images from ECR, ships logs to CloudWatch, and
# injects the DB password into the container as a secret at start time.
# Deliberately not the AWS-managed AmazonECSTaskExecutionRolePolicy — that
# policy's ecr:GetAuthorizationToken/BatchGetImage/GetDownloadUrlForLayer
# grants apply account-wide; this scopes image pulls and log writes to only
# this project's ECR repos and log groups.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "ecs_task_execution" {
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"] # this action has no resource-level permissions; must be "*"
    resources = ["*"]
  }

  statement {
    sid = "ECRPullThisProjectOnly"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [local.ecr_repo_arn_pattern]
  }

  statement {
    sid = "LogsThisProjectOnly"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [local.log_group_arn_pattern]
  }

  statement {
    sid       = "ReadDbPasswordSecretOnly"
    actions   = ["ssm:GetParameters"]
    resources = [var.db_password_ssm_param_arn]
  }

  statement {
    # SSM SecureString values are encrypted with the AWS-managed
    # "alias/aws/ssm" key. Decrypt requires the actual key resource, and an
    # alias ARN doesn't grant on the underlying key — so this uses "*" with
    # a kms:ViaService condition restricting it to only fire when SSM (in
    # this region) is the service asking, which is the AWS-documented
    # pattern for consuming the default SSM-managed key. It cannot be used
    # to decrypt anything outside an SSM GetParameter(s) call in this
    # region.
    sid       = "DecryptViaSsmOnly"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "ecs_task_execution" {
  name   = "${local.name}-ecs-task-execution"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_task_execution.json
}

# ---------------------------------------------------------------------------
# Product service task role — the app code's own permissions. Read/write
# on the products table and its category GSI only.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "product_task" {
  name               = "${local.name}-product-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "product_task" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
    ]
    resources = [
      var.products_table_arn,
      "${var.products_table_arn}/index/*",
    ]
  }
}

resource "aws_iam_role_policy" "product_task" {
  name   = "${local.name}-product-task"
  role   = aws_iam_role.product_task.id
  policy = data.aws_iam_policy_document.product_task.json
}

# ---------------------------------------------------------------------------
# Cart service task role — read/write on the cart table only.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "cart_task" {
  name               = "${local.name}-cart-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "cart_task" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
    ]
    resources = [var.cart_table_arn]
  }
}

resource "aws_iam_role_policy" "cart_task" {
  name   = "${local.name}-cart-task"
  role   = aws_iam_role.cart_task.id
  policy = data.aws_iam_policy_document.cart_task.json
}

# ---------------------------------------------------------------------------
# User service task role — Cognito admin actions scoped to this project's
# user pool only, for account-management endpoints (e.g. an admin viewing
# or updating a user record). No account/pool creation or deletion rights.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "user_task" {
  name               = "${local.name}-user-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "user_task" {
  statement {
    actions = [
      "cognito-idp:AdminGetUser",
      "cognito-idp:AdminUpdateUserAttributes",
      "cognito-idp:AdminDeleteUser",
    ]
    resources = [var.cognito_user_pool_arn]
  }
}

resource "aws_iam_role_policy" "user_task" {
  name   = "${local.name}-user-task"
  role   = aws_iam_role.user_task.id
  policy = data.aws_iam_policy_document.user_task.json
}

# ---------------------------------------------------------------------------
# Order service task role — read-only on the products table (to validate
# items/prices when an order is placed), plus sns:Publish on the
# order-events topic only. RDS access is network-level only (via the
# rds-sg + DB username/password, not IAM), so no RDS IAM permissions are
# needed here. No sqs:SendMessage — the order-service publishes to SNS
# only; SNS itself (not the app) delivers into the shipping queue via its
# subscription, so the task role never needs direct SQS access.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "order_task" {
  name               = "${local.name}-order-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "order_task" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      var.products_table_arn,
      "${var.products_table_arn}/index/*",
    ]
  }

  statement {
    actions   = ["sns:Publish"]
    resources = [var.order_events_topic_arn]
  }
}

resource "aws_iam_role_policy" "order_task" {
  name   = "${local.name}-order-task"
  role   = aws_iam_role.order_task.id
  policy = data.aws_iam_policy_document.order_task.json
}
