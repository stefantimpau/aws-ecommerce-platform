terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Same pattern as the dns module: a WAF Web ACL scoped to CLOUDFRONT
      # must be created in us-east-1 no matter which region the rest of
      # the stack runs in. The API Gateway Web ACL is REGIONAL and uses
      # the default (eu-west-2) provider instead.
      configuration_aliases = [aws.us_east_1]
    }
  }
}

locals {
  name = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# CloudFront Web ACL — build step 20. Sits in front of the frontend
# distribution. Three AWS managed rule groups (free, no extra cost beyond
# the ACL + request volume) cover the OWASP-style basics, then a
# rate-based rule catches simple scraping/DoS attempts that don't match
# any signature. Every rule runs in COUNT during initial rollout would be
# safer, but this is a portfolio demo with low real traffic, so BLOCK is
# used directly — see the README's Incident Notes if a legitimate request
# ever gets caught by this.
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "cloudfront" {
  provider    = aws.us_east_1
  name        = "${local.name}-cloudfront"
  description = "WAF for the CloudFront-served frontend"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "aws-common-rule-set"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-cloudfront-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-known-bad-inputs"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-cloudfront-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limit"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-cloudfront-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-cloudfront"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-cloudfront-waf"
  })
}

# ---------------------------------------------------------------------------
# API Gateway Web ACL — build step 20. Adds a SQLi rule group on top of the
# same common/bad-inputs coverage, since this is the ACL sitting in front
# of the actual data layer (RDS + DynamoDB), not just static assets. A
# tighter rate limit than the frontend, since the API has no CDN caching
# to absorb a burst.
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "api" {
  name        = "${local.name}-api"
  description = "WAF for the API Gateway custom domain"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "aws-common-rule-set"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-known-bad-inputs"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-sqli-rule-set"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-sqli"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limit"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.api_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-api"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-api-waf"
  })
}
