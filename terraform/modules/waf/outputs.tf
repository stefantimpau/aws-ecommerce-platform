output "cloudfront_web_acl_arn" {
  value = aws_wafv2_web_acl.cloudfront.arn
}

output "cloudfront_web_acl_id" {
  value = aws_wafv2_web_acl.cloudfront.id
}

output "api_web_acl_arn" {
  value = aws_wafv2_web_acl.api.arn
}

output "api_web_acl_id" {
  value = aws_wafv2_web_acl.api.id
}
