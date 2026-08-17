output "parameter_prefix" {
  description = "Common SSM path prefix used by every parameter this module (and the rds module) creates"
  value       = local.prefix
}

output "parameter_arns" {
  description = "ARNs of every non-secret config parameter — useful for scoping an IAM read policy"
  value = [
    aws_ssm_parameter.region.arn,
    aws_ssm_parameter.cognito_user_pool_id.arn,
    aws_ssm_parameter.cognito_user_pool_client_id.arn,
    aws_ssm_parameter.cognito_issuer_url.arn,
    aws_ssm_parameter.dynamodb_products_table.arn,
    aws_ssm_parameter.dynamodb_cart_table.arn,
    aws_ssm_parameter.frontend_bucket_name.arn,
    aws_ssm_parameter.images_bucket_name.arn,
    aws_ssm_parameter.cloudfront_domain_name.arn,
  ]
}
