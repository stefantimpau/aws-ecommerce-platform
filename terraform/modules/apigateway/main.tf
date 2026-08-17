locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)

  # Every route in the storefront's API surface, keyed by its
  # "METHOD /path" route key (matches services/*/src/index.js exactly —
  # see each service's Express routes). `requires_auth = false` is
  # deliberately narrow: only the public catalog reads skip the Cognito
  # JWT authorizer, everything else (writes, cart, user, orders) requires
  # a valid token.
  routes = {
    "GET /products"              = { requires_auth = false }
    "GET /products/{proxy+}"     = { requires_auth = false }
    "POST /products"             = { requires_auth = true }
    "DELETE /products/{proxy+}"  = { requires_auth = true }
    "ANY /cart/{proxy+}"         = { requires_auth = true }
    "ANY /users/{proxy+}"        = { requires_auth = true }
    "GET /orders/{proxy+}"       = { requires_auth = true }
    "POST /orders"               = { requires_auth = true }
  }
}

# ---------------------------------------------------------------------------
# VPC Link — build order step 16. The bridge that lets a regional (public)
# API Gateway HTTP API reach a resource with no public IP (the internal
# ALB, deep in the private-app subnets). This was the second load-balancer-
# adjacent resource checkpointed on the account restriction noted in the
# README's Incident Notes — the ALB itself unblocked step 14/15, this
# unblocks the public entry point.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${local.name}-vpc-link"
  security_group_ids = [var.security_group_id]
  subnet_ids         = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpc-link"
  })
}

# ---------------------------------------------------------------------------
# HTTP API — cheaper and simpler than a REST API for this use case (no
# usage plans / API keys / request validation needed for a portfolio
# storefront). CORS is configured here rather than per-route since every
# route shares the same frontend origin.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins     = var.cors_allow_origins
    allow_methods     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers     = ["Content-Type", "Authorization"]
    allow_credentials = true
    max_age           = 300
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-api"
  })
}

# ---------------------------------------------------------------------------
# Cognito JWT authorizer — validates the SPA's Cognito-issued access token
# on every route except the public catalog reads. API Gateway does the
# validation itself (signature, expiry, issuer, audience); a request that
# fails never reaches the ALB or the ECS tasks.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  name             = "${local.name}-cognito-jwt"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [var.cognito_user_pool_client_id]
    issuer   = var.cognito_issuer_url
  }
}

# ---------------------------------------------------------------------------
# Single integration, reused by every route — the internal ALB already
# does path-based routing to the right service (terraform/modules/alb
# listener rules), so API Gateway just needs to hand the request off
# through the VPC Link.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = var.alb_listener_arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id

  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"

  authorization_type = each.value.requires_auth ? "JWT" : "NONE"
  authorizer_id       = each.value.requires_auth ? aws_apigatewayv2_authorizer.cognito.id : null
}

# ---------------------------------------------------------------------------
# $default stage, auto-deployed — every route change takes effect
# immediately without a separate deployment step. Access logs go to their
# own log group so API-level request patterns (path, status, latency) are
# queryable independent of the per-service ECS container logs.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "access_logs" {
  name              = "/apigateway/${local.name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "/apigateway/${local.name}"
  })
}

# ---------------------------------------------------------------------------
# Custom domain — build step 19. The api_subdomain cert was already
# validated back in step 12 (terraform/modules/dns); this just attaches
# it to the API. Conditional on custom_domain_name being set so the
# module keeps working against the default execute-api.* URL before
# step 19 wires the real domain in.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_domain_name" "this" {
  count       = var.custom_domain_name != "" ? 1 : 0
  domain_name = var.custom_domain_name

  domain_name_configuration {
    certificate_arn = var.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_api_mapping" "this" {
  count       = var.custom_domain_name != "" ? 1 : 0
  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this[0].id
  stage       = aws_apigatewayv2_stage.default.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      integrationErr = "$context.integrationErrorMessage"
      responseLength = "$context.responseLength"
      requestTime    = "$context.requestTime"
    })
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Build step 20 note: AWS WAF does NOT support association with API
# Gateway HTTP APIs (this module's aws_apigatewayv2_* resources) — only
# REST APIs (v1), ALB, CloudFront, AppSync, Cognito, App Runner, and
# Verified Access. An aws_wafv2_web_acl_association pointed at this
# stage's ARN fails with "The ARN isn't valid" no matter how the $default
# segment is encoded, because the resource type itself isn't a supported
# WAF target, not because of an encoding issue. See the README's Incident
# Notes and terraform/modules/alb/main.tf — the API's Web ACL is attached
# to the internal ALB instead, one hop downstream, since every request
# that reaches this API passes through it anyway.
# ---------------------------------------------------------------------------
