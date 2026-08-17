output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  value = module.vpc.private_app_subnet_ids
}

output "private_data_subnet_ids" {
  value = module.vpc.private_data_subnet_ids
}

output "nat_gateway_ids" {
  value = module.vpc.nat_gateway_ids
}

output "alb_sg_id" {
  value = module.security_groups.alb_sg_id
}

output "ecs_tasks_sg_id" {
  value = module.security_groups.ecs_tasks_sg_id
}

output "rds_sg_id" {
  value = module.security_groups.rds_sg_id
}

output "db_address" {
  value = module.rds.db_address
}

output "db_password_ssm_param_name" {
  value = module.rds.db_password_ssm_param_name
}

output "products_table_name" {
  value = module.dynamodb.products_table_name
}

output "cart_table_name" {
  value = module.dynamodb.cart_table_name
}

output "frontend_bucket_name" {
  value = module.static_frontend.frontend_bucket_name
}

output "images_bucket_name" {
  value = module.static_frontend.images_bucket_name
}

output "cloudfront_domain_name" {
  value = module.static_frontend.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "Used by scripts/deploy-frontend.sh to invalidate the cache after each deploy"
  value       = module.static_frontend.cloudfront_distribution_id
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_user_pool_client_id" {
  value = module.cognito.user_pool_client_id
}

output "cognito_issuer_url" {
  value = module.cognito.issuer_url
}

output "cognito_hosted_ui_domain" {
  value = module.cognito.hosted_ui_domain
}

output "ssm_parameter_prefix" {
  value = module.ssm_config.parameter_prefix
}

output "ecs_task_execution_role_arn" {
  value = module.iam.ecs_task_execution_role_arn
}

output "product_task_role_arn" {
  value = module.iam.product_task_role_arn
}

output "cart_task_role_arn" {
  value = module.iam.cart_task_role_arn
}

output "user_task_role_arn" {
  value = module.iam.user_task_role_arn
}

output "order_task_role_arn" {
  value = module.iam.order_task_role_arn
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_task_definition_arns" {
  value = module.ecs.task_definition_arns
}

output "ecs_log_group_names" {
  value = module.ecs.log_group_names
}

output "ecs_service_names" {
  value = module.ecs.service_names
}

output "internal_alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "internal_alb_target_group_arns" {
  value = module.alb.target_group_arns
}

output "api_gateway_endpoint" {
  description = "Default execute-api invoke URL — usable for testing before the custom domain (build step 19) is wired up"
  value       = module.apigateway.api_endpoint
}

output "frontend_url" {
  description = "The real, custom-domain frontend URL (build step 19)"
  value       = "https://${module.dns.frontend_subdomain}"
}

output "api_url" {
  description = "The real, custom-domain API URL (build step 19)"
  value       = "https://${module.dns.api_subdomain}"
}

output "order_events_topic_arn" {
  value = module.notifications.order_events_topic_arn
}

output "shipping_queue_url" {
  value = module.notifications.shipping_queue_url
}

output "route53_zone_id" {
  value = module.dns.zone_id
}

output "frontend_certificate_arn" {
  value = module.dns.frontend_certificate_arn
}

output "api_certificate_arn" {
  value = module.dns.api_certificate_arn
}

output "frontend_subdomain" {
  value = module.dns.frontend_subdomain
}

output "api_subdomain" {
  value = module.dns.api_subdomain
}

output "cloudfront_web_acl_arn" {
  value = module.waf.cloudfront_web_acl_arn
}

output "api_web_acl_arn" {
  value = module.waf.api_web_acl_arn
}

output "budget_name" {
  value = module.budget.budget_name
}

output "ops_alerts_topic_arn" {
  value = module.observability.ops_alerts_topic_arn
}

output "cloudwatch_dashboard_url" {
  value = module.observability.dashboard_url
}

output "github_deploy_role_arn" {
  description = "Only present when enable_github_oidc = true. Set this as the AWS_DEPLOY_ROLE_ARN repo variable in GitHub for .github/workflows/deploy.yml."
  value       = var.enable_github_oidc ? module.github_oidc[0].deploy_role_arn : null
}
