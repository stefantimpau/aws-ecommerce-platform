locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# S3 buckets — both fully private. All access goes through CloudFront via
# Origin Access Control; nothing is reachable by hitting the bucket
# directly, even if someone has the bucket name.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name}-frontend-${data.aws_caller_identity.current.account_id}"

  # This is a portfolio project torn down between demo sessions (see
  # scripts/teardown/destroy.sh) — force_destroy lets `terraform destroy`
  # remove the bucket even with objects still in it (every deploy leaves
  # a fresh React build in here), rather than failing with
  # BucketNotEmpty and requiring a manual empty step first.
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-frontend"
  })
}

resource "aws_s3_bucket" "images" {
  bucket = "${local.name}-product-images-${data.aws_caller_identity.current.account_id}"

  # Same reasoning as the frontend bucket above — product images seeded
  # by scripts/seed/seed.js shouldn't block a clean teardown.
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-product-images"
  })
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled" # cheap safety net for accidental bad deploys — old build objects are easy to prune later
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# Origin Access Control — one OAC, reused for both S3 origins. This is what
# lets CloudFront sign requests to S3 without the buckets being public.
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${local.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------------------------------------
# CloudFront distribution — default behavior serves the React build from
# the frontend bucket; /images/* is routed to the product-images bucket.
# SPA client-side routing is handled by mapping 403/404 back to
# /index.html with a 200, since S3 has no concept of React Router routes.
# ---------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = var.price_class
  comment             = "${local.name} frontend + product images"
  aliases             = var.aliases

  # Build step 20 — empty string is CloudFront's own way of saying "no
  # WAF attached", so this works before the waf module exists in the
  # root wiring and after, with no conditional needed.
  web_acl_id = var.web_acl_id

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "frontend-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  origin {
    domain_name              = aws_s3_bucket.images.bucket_regional_domain_name
    origin_id                = "images-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods          = ["GET", "HEAD"]
    target_origin_id        = "frontend-s3"
    viewer_protocol_policy  = "redirect-to-https"
    compress                = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  ordered_cache_behavior {
    path_pattern            = "/images/*"
    allowed_methods         = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "images-s3"
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 604800
  }

  # SPA routing: any path S3 doesn't have an object for (client-side routes
  # like /products/123) comes back as 403 from S3-via-OAC; rewrite that to
  # index.html so React Router can take over.
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # build order step 19: an ACM cert (us-east-1, from the dns module) +
  # alternate domain name (var.aliases, above) once both are supplied.
  # Falls back to the default *.cloudfront.net cert if not — lets this
  # module keep working standalone before step 19 wires the real domain
  # in, without a second copy of this resource.
  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == "" ? true : null
    acm_certificate_arn            = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    ssl_support_method             = var.acm_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != "" ? "TLSv1.2_2021" : null
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-cdn"
  })
}

# ---------------------------------------------------------------------------
# Bucket policies — allow only this specific CloudFront distribution
# (via AWS:SourceArn) to read via the OAC-signed service principal.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "frontend" {
  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

data "aws_iam_policy_document" "images" {
  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.images.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend.json
}

resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id
  policy = data.aws_iam_policy_document.images.json
}
