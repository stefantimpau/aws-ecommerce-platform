output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Default execute-api invoke URL — usable for end-to-end testing before the custom domain (build step 19) is wired up"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "vpc_link_id" {
  value = aws_apigatewayv2_vpc_link.this.id
}

output "authorizer_id" {
  value = aws_apigatewayv2_authorizer.cognito.id
}

output "custom_domain_target" {
  description = "The API Gateway-managed regional domain target — the alias target for the Route 53 record pointing custom_domain_name at this API. Empty if custom_domain_name wasn't set."
  value       = try(aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name, "")
}

output "custom_domain_zone_id" {
  description = "Alias zone ID for the same Route 53 record"
  value       = try(aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].hosted_zone_id, "")
}
