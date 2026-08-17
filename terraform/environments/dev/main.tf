data "aws_caller_identity" "current" {}

module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment

  vpc_cidr                  = var.vpc_cidr
  azs                        = var.azs
  public_subnet_cidrs       = var.public_subnet_cidrs
  private_app_subnet_cidrs  = var.private_app_subnet_cidrs
  private_data_subnet_cidrs = var.private_data_subnet_cidrs
  single_nat_gateway         = var.single_nat_gateway
}

module "security_groups" {
  source = "../../modules/security-groups"

  project     = var.project
  environment = var.environment

  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  private_data_subnet_ids = module.vpc.private_data_subnet_ids
  vpc_security_group_ids  = [module.security_groups.rds_sg_id]
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  project     = var.project
  environment = var.environment
}

module "waf" {
  source = "../../modules/waf"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project     = var.project
  environment = var.environment
}

module "static_frontend" {
  source = "../../modules/static-frontend"

  project     = var.project
  environment = var.environment

  # Build step 19 — custom domain on CloudFront. The cert was already
  # validated back in step 12 (terraform/modules/dns).
  aliases              = [module.dns.frontend_subdomain]
  acm_certificate_arn  = module.dns.frontend_certificate_arn

  # Build step 20.
  web_acl_id = module.waf.cloudfront_web_acl_arn
}

module "cognito" {
  source = "../../modules/cognito"

  project     = var.project
  environment = var.environment

  # Both the custom domain (step 19) and the default CloudFront domain
  # stay valid callback targets — keeps localhost dev and the raw
  # *.cloudfront.net URL working alongside the real shop.stefantimpau.com
  # domain, rather than a hard cutover that breaks one or the other.
  callback_urls = [
    "http://localhost:3000",
    "https://${module.static_frontend.cloudfront_domain_name}",
    "https://${module.dns.frontend_subdomain}",
  ]
  logout_urls = [
    "http://localhost:3000",
    "https://${module.static_frontend.cloudfront_domain_name}",
    "https://${module.dns.frontend_subdomain}",
  ]
}

module "ssm_config" {
  source = "../../modules/ssm-config"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  cognito_user_pool_id        = module.cognito.user_pool_id
  cognito_user_pool_client_id = module.cognito.user_pool_client_id
  cognito_issuer_url          = module.cognito.issuer_url

  dynamodb_products_table = module.dynamodb.products_table_name
  dynamodb_cart_table     = module.dynamodb.cart_table_name

  frontend_bucket_name    = module.static_frontend.frontend_bucket_name
  images_bucket_name      = module.static_frontend.images_bucket_name
  cloudfront_domain_name  = module.static_frontend.cloudfront_domain_name

  api_base_url = module.apigateway.api_endpoint
}

module "notifications" {
  source = "../../modules/notifications"

  project     = var.project
  environment = var.environment

  # No default anywhere — must be supplied with -var or
  # TF_VAR_notification_email at apply time so it never lands in a
  # committed file in this public repo.
  notification_email = var.notification_email
}

module "iam" {
  source = "../../modules/iam"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  products_table_arn         = module.dynamodb.products_table_arn
  cart_table_arn              = module.dynamodb.cart_table_arn
  cognito_user_pool_arn       = module.cognito.user_pool_arn
  db_password_ssm_param_arn   = module.rds.db_password_ssm_param_arn
  order_events_topic_arn      = module.notifications.order_events_topic_arn
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment
  services    = ["product", "cart", "user", "order"]
}

module "ecs" {
  source = "../../modules/ecs"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  execution_role_arn     = module.iam.ecs_task_execution_role_arn
  product_task_role_arn  = module.iam.product_task_role_arn
  cart_task_role_arn     = module.iam.cart_task_role_arn
  user_task_role_arn     = module.iam.user_task_role_arn
  order_task_role_arn    = module.iam.order_task_role_arn

  ecr_repository_urls = module.ecr.repository_urls
  image_tag            = var.image_tag

  dynamodb_products_table = module.dynamodb.products_table_name
  dynamodb_cart_table     = module.dynamodb.cart_table_name
  cognito_user_pool_id    = module.cognito.user_pool_id

  db_host                    = module.rds.db_address
  db_port                     = module.rds.db_port
  db_name                     = module.rds.db_name
  db_username                 = module.rds.db_username
  db_password_ssm_param_arn   = module.rds.db_password_ssm_param_arn

  order_events_topic_arn = module.notifications.order_events_topic_arn

  private_app_subnet_ids = module.vpc.private_app_subnet_ids
  ecs_tasks_sg_id         = module.security_groups.ecs_tasks_sg_id

  # Build step 15: the internal ALB (step 14) and its target groups now
  # exist, so attach the ECS services to them. This updates the existing
  # services in place (adds a load_balancer block) rather than recreating
  # them — desired count and task definitions are untouched.
  attach_load_balancer = true
  target_group_arns    = module.alb.target_group_arns
}

module "alb" {
  source = "../../modules/alb"

  project     = var.project
  environment = var.environment

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_app_subnet_ids
  security_group_id  = module.security_groups.alb_sg_id

  # Build step 20 — the api Web ACL attaches HERE, not to the API Gateway
  # HTTP API below, because AWS WAF doesn't support HTTP APIs as an
  # association target at all (see terraform/modules/apigateway/main.tf's
  # comment — this was discovered the hard way, apply failing with "The
  # ARN isn't valid" no matter how the $default stage segment was
  # encoded). The ALB is a supported target and sees the exact same
  # traffic one hop later.
  attach_web_acl = true
  web_acl_arn    = module.waf.api_web_acl_arn
}

module "apigateway" {
  source = "../../modules/apigateway"

  project     = var.project
  environment = var.environment

  subnet_ids         = module.vpc.private_app_subnet_ids
  security_group_id  = module.security_groups.vpc_link_sg_id
  alb_listener_arn   = module.alb.alb_listener_arn

  cognito_issuer_url          = module.cognito.issuer_url
  cognito_user_pool_client_id = module.cognito.user_pool_client_id

  # Build step 19 — custom domain on the API itself. Cert already
  # validated back in step 12.
  custom_domain_name = module.dns.api_subdomain
  certificate_arn     = module.dns.api_certificate_arn

  # Both the custom frontend domain and the default CloudFront domain are
  # allowed to call this API — same reasoning as the Cognito callback
  # URLs above.
  cors_allow_origins = [
    "http://localhost:3000",
    "https://${module.static_frontend.cloudfront_domain_name}",
    "https://${module.dns.frontend_subdomain}",
  ]
}

module "dns" {
  source = "../../modules/dns"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project     = var.project
  environment = var.environment

  # Reuses the existing stefantimpau.com Route 53 zone (data source, not a
  # new zone) — see docs/adr/0003-subdomain-not-new-domain.md for why no
  # new domain was purchased for a project torn down within days.
  root_domain        = "stefantimpau.com"
  frontend_subdomain = "shop.stefantimpau.com"
  api_subdomain       = "api.shop.stefantimpau.com"
}

# ---------------------------------------------------------------------------
# Build step 19 — the actual DNS records pointing the custom domains at
# their services. Deliberately root-level resources, not inside the dns
# module: the dns module issues the certs that static_frontend and
# apigateway consume, so it can't also depend on THEIR outputs (the
# CloudFront/API Gateway domain targets) without a circular module
# dependency. The root module has no such restriction.
# ---------------------------------------------------------------------------

resource "aws_route53_record" "frontend" {
  zone_id = module.dns.zone_id
  name    = module.dns.frontend_subdomain
  type    = "A"

  alias {
    name = module.static_frontend.cloudfront_domain_name
    # Fixed, global CloudFront hosted zone ID — the same for every
    # CloudFront distribution in every account, not specific to this one.
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api" {
  zone_id = module.dns.zone_id
  name    = module.dns.api_subdomain
  type    = "A"

  alias {
    name                   = module.apigateway.custom_domain_target
    zone_id                = module.apigateway.custom_domain_zone_id
    evaluate_target_health = false
  }
}

module "budget" {
  source = "../../modules/budget"

  project     = var.project
  environment = var.environment

  # Same address as the ops-alerts and order-events notifications — see
  # module.observability and module.notifications below for why those
  # stay on separate SNS topics even sharing this inbox; a budget alert
  # is a third, distinct kind of notification for the same reason.
  notification_email = var.notification_email
}

module "observability" {
  source = "../../modules/observability"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  # Same dedicated contact address as order-events, but a SEPARATE SNS
  # topic — see the module's comment on why infra alarms and order
  # confirmations shouldn't share a channel even when they currently
  # share an inbox.
  ops_alert_email = var.notification_email

  ecs_cluster_name  = module.ecs.cluster_name
  ecs_service_names = module.ecs.service_names

  db_instance_id  = module.rds.db_instance_id
  nat_gateway_id  = module.vpc.nat_gateway_ids[0]

  dynamodb_products_table = module.dynamodb.products_table_name
  dynamodb_cart_table     = module.dynamodb.cart_table_name
}

# ---------------------------------------------------------------------------
# Build step 22 (CI/CD, stretch goal) — the IAM identity GitHub Actions'
# deploy workflow assumes via OIDC, no long-lived access keys stored as a
# GitHub secret. Off by default (enable_github_oidc = false) until the repo
# actually exists on GitHub and var.github_repo is set to its real
# "owner/repo" — see .github/workflows/deploy.yml and the README's CI/CD
# section for the one-time setup steps (bootstrap state bucket, this
# module, then the repo variable pointing at deploy_role_arn below).
# ---------------------------------------------------------------------------

module "github_oidc" {
  source = "../../modules/github-oidc"
  count  = var.enable_github_oidc ? 1 : 0

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  github_repo = var.github_repo

  ecr_repository_arns = values(module.ecr.repository_arns)

  ecs_cluster_arn                 = module.ecs.cluster_arn
  ecs_service_arns                = values(module.ecs.service_arns)
  ecs_task_definition_family_arns = values(module.ecs.task_definition_family_arns)

  passable_role_arns = [
    module.iam.ecs_task_execution_role_arn,
    module.iam.product_task_role_arn,
    module.iam.cart_task_role_arn,
    module.iam.user_task_role_arn,
    module.iam.order_task_role_arn,
  ]

  # Deterministic S3 bucket ARN from the name — the static-frontend module
  # doesn't output the ARN itself (only the bucket name/id), and bucket
  # ARNs are just "arn:aws:s3:::<bucket-name>" with no account/region
  # segment, so this is safe to construct rather than adding a new output.
  state_bucket_arn    = "arn:aws:s3:::${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  frontend_bucket_arn = "arn:aws:s3:::${module.static_frontend.frontend_bucket_name}"

  cloudfront_distribution_arn = module.static_frontend.cloudfront_distribution_arn
}
