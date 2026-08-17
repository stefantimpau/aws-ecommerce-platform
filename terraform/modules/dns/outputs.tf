output "zone_id" {
  value = data.aws_route53_zone.this.zone_id
}

output "frontend_certificate_arn" {
  description = "Validated us-east-1 cert — pass to CloudFront's viewer_certificate in build step 19"
  value       = aws_acm_certificate_validation.frontend.certificate_arn
}

output "api_certificate_arn" {
  description = "Validated eu-west-2 cert — pass to the API Gateway custom domain in build step 19"
  value       = aws_acm_certificate_validation.api.certificate_arn
}

output "frontend_subdomain" {
  value = var.frontend_subdomain
}

output "api_subdomain" {
  value = var.api_subdomain
}
