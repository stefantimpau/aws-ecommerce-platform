terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      # This module needs two providers: the default (eu-west-2, for the
      # regional API Gateway cert) and an explicit us-east-1 alias, since
      # ACM certificates used by CloudFront MUST be requested in us-east-1
      # regardless of which region everything else lives in. The caller
      # (environments/dev) passes both in via the `providers` block.
      configuration_aliases = [aws.us_east_1]
    }
  }
}

locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# Looks up the EXISTING hosted zone for the user's domain — deliberately a
# data source, not a resource. The user already manages stefantimpau.com
# in Route 53 for their portfolio site; creating a second zone for the
# same domain would be wrong (conflicting NS records) and buying a whole
# new domain for a demo that's torn down in days isn't worth the recurring
# cost — see docs/adr/0003-subdomain-not-new-domain.md.
data "aws_route53_zone" "this" {
  name         = var.root_domain
  private_zone = false
}

# ---------------------------------------------------------------------------
# Frontend certificate — CloudFront requires ACM certs in us-east-1,
# always, regardless of the distribution's actual edge locations.
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "frontend" {
  provider          = aws.us_east_1
  domain_name       = var.frontend_subdomain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-frontend-cert"
  })
}

resource "aws_route53_record" "frontend_validation" {
  for_each = {
    for dvo in aws_acm_certificate.frontend.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "frontend" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.frontend.arn
  validation_record_fqdns = [for r in aws_route53_record.frontend_validation : r.fqdn]
}

# ---------------------------------------------------------------------------
# API certificate — a regional API Gateway custom domain needs its cert in
# the SAME region as the API (eu-west-2 here), not us-east-1.
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "api" {
  domain_name       = var.api_subdomain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-api-cert"
  })
}

resource "aws_route53_record" "api_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for r in aws_route53_record.api_validation : r.fqdn]
}
