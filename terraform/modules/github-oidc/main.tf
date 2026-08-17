# Lets GitHub Actions assume an IAM role directly via OIDC federation, so
# the deploy workflow never needs long-lived AWS access keys stored as a
# GitHub secret — the standard, more-secure alternative to static
# credentials. See ADR 0004 for why this role's permissions are scoped to
# "redeploy application code" only (ECR push, ECS task-def/service
# update, frontend S3 sync, CloudFront invalidation) rather than the full
# `terraform apply` surface this project's infrastructure needs.

locals {
  name = "${var.project}-${var.environment}-github-deploy"
}

data "aws_caller_identity" "current" {}

# GitHub's own documented OIDC root-CA thumbprints for
# token.actions.githubusercontent.com. AWS no longer actually validates
# against these (it trusts the provider's TLS cert chain directly since
# 2023), but the field is still required at creation time.
locals {
  github_oidc_thumbprints = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = local.github_oidc_thumbprints

  tags = merge(var.tags, { Name = "github-actions-oidc" })
}

# If a prior project in this account already created the provider,
# create_oidc_provider = false and this data source finds it instead.
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to this exact repo, any branch/ref/PR — NOT a wildcard across
    # all of GitHub. Tighten further to e.g. "repo:${var.github_repo}:ref:refs/heads/main"
    # if this role should only ever be assumable from main.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*", "repo:stefantimpau@309347932/aws-ecommerce-platform@1337033563:*"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = merge(var.tags, { Name = local.name })
}

data "aws_iam_policy_document" "deploy" {
  # ECR: log in and push to exactly the four service repos. GetAuthorizationToken
  # has no resource-level permissions in IAM — it's always "*".
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
    ]
    resources = var.ecr_repository_arns
  }

  # ECS: register a new task-definition revision per service and point
  # each service at it. RegisterTaskDefinition has no resource-level
  # permissions (AWS limitation) so it's granted on "*"; everything else
  # here is scoped to this project's cluster/services/families.
  statement {
    sid       = "EcsRegisterTaskDef"
    effect    = "Allow"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid    = "EcsDescribeAndDeploy"
    effect = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:DeregisterTaskDefinition",
    ]
    resources = var.ecs_task_definition_family_arns
  }

  statement {
    sid    = "EcsUpdateServices"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = var.ecs_service_arns
  }

  statement {
    sid       = "EcsDescribeCluster"
    effect    = "Allow"
    actions   = ["ecs:DescribeClusters"]
    resources = [var.ecs_cluster_arn]
  }

  # Registering a task definition that references the execution role and
  # each task role requires explicit permission to pass those roles to
  # ECS — without this, RegisterTaskDefinition fails even with the ecs:*
  # actions above.
  statement {
    sid       = "PassEcsRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = var.passable_role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # Terraform remote state — read/write the state object and acquire the
  # native S3 lock (a conditional write to the same key, no separate
  # DynamoDB table).
  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [var.state_bucket_arn, "${var.state_bucket_arn}/*"]
  }

  # Frontend deploy: sync the built React app to S3 and invalidate the
  # CloudFront cache so it's actually served.
  statement {
    sid    = "FrontendSync"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [var.frontend_bucket_arn, "${var.frontend_bucket_arn}/*"]
  }

  statement {
    sid       = "CloudFrontInvalidate"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [var.cloudfront_distribution_arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = local.name
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
