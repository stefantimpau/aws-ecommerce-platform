locals {
  # SSM Parameter Store rejects any parameter path starting with the
  # reserved "aws" prefix. var.project is "aws-ecommerce-platform", so
  # strip the leading "aws-" before building the path (same fix as the
  # rds module, applied identically so both modules produce the same
  # non-reserved prefix shape).
  prefix      = "/${replace(var.project, "aws-", "")}/${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# General config as SSM String parameters. Nothing here is secret — actual
# secrets (DB password) live in the rds module as a SecureString. ECS task
# definitions read these at container start instead of baking config into
# the image, so the same image works unchanged across environments.
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "region" {
  name  = "${local.prefix}/region"
  type  = "String"
  value = var.aws_region
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "cognito_user_pool_id" {
  name  = "${local.prefix}/cognito/user_pool_id"
  type  = "String"
  value = var.cognito_user_pool_id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "cognito_user_pool_client_id" {
  name  = "${local.prefix}/cognito/user_pool_client_id"
  type  = "String"
  value = var.cognito_user_pool_client_id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "cognito_issuer_url" {
  name  = "${local.prefix}/cognito/issuer_url"
  type  = "String"
  value = var.cognito_issuer_url
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "dynamodb_products_table" {
  name  = "${local.prefix}/dynamodb/products_table"
  type  = "String"
  value = var.dynamodb_products_table
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "dynamodb_cart_table" {
  name  = "${local.prefix}/dynamodb/cart_table"
  type  = "String"
  value = var.dynamodb_cart_table
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "frontend_bucket_name" {
  name  = "${local.prefix}/s3/frontend_bucket"
  type  = "String"
  value = var.frontend_bucket_name
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "images_bucket_name" {
  name  = "${local.prefix}/s3/images_bucket"
  type  = "String"
  value = var.images_bucket_name
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "cloudfront_domain_name" {
  name  = "${local.prefix}/cloudfront/domain_name"
  type  = "String"
  value = var.cloudfront_domain_name
  tags  = local.common_tags
}

# API Gateway now exists (build step 16/17) — this is the frontend's
# backend base URL, read at build time in step 18.
resource "aws_ssm_parameter" "api_base_url" {
  name  = "${local.prefix}/api/base_url"
  type  = "String"
  value = var.api_base_url
  tags  = local.common_tags
}
