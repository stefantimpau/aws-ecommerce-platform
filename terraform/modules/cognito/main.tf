data "aws_region" "current" {}

locals {
  name = "${var.project}-${var.environment}"
  # Cognito rejects any hosted-UI domain containing the reserved word "aws"
  # as a substring. var.project is "aws-ecommerce-platform", so build the
  # domain from a stripped version instead of local.name.
  domain_safe_name = replace(local.name, "aws-", "")
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# User Pool — email as the sign-in identifier (no separate username), email
# verification required before the account is usable, strong password
# policy. MFA left optional/off by default to keep the demo flow simple —
# noted here as a trade-off, not an oversight: a real production pool for
# a payment-adjacent app would default MFA to required.
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool" "this" {
  name = "${local.name}-users"

  username_attributes     = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                  = 12
    require_lowercase               = true
    require_uppercase               = true
    require_numbers                 = true
    require_symbols                 = true
    temporary_password_validity_days = 7
  }

  mfa_configuration = "OFF"

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false # self-service sign-up, this is a public storefront
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-user-pool"
  })
}

# ---------------------------------------------------------------------------
# App client — public client (no secret), used by the React SPA. Auth flows
# limited to what a browser-based public client should use: SRP for direct
# sign-in, and the Authorization Code + PKCE flow for the hosted UI /
# OAuth path. No client-credentials or admin-only flows.
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool_client" "spa" {
  name         = "${local.name}-spa-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false # public client — a secret can't be kept safe in browser JS anyway

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  supported_identity_providers = ["COGNITO"]

  access_token_validity  = 60   # minutes
  id_token_validity      = 60   # minutes
  refresh_token_validity = 30   # days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED" # don't leak whether an email is registered
}

# ---------------------------------------------------------------------------
# Hosted UI domain — a Cognito-managed domain (no custom-domain cert needed
# here since it's under *.auth.<region>.amazoncognito.com), so it's usable
# immediately without waiting on the ACM/Route 53 work in step 12.
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${local.domain_safe_name}-auth"
  user_pool_id = aws_cognito_user_pool.this.id
}
