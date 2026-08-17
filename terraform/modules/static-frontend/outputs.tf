output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.id
}

output "images_bucket_name" {
  value = aws_s3_bucket.images.id
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "cloudfront_distribution_arn" {
  value = aws_cloudfront_distribution.this.arn
}

output "cloudfront_domain_name" {
  description = "Default *.cloudfront.net domain — usable as-is until the custom domain (build step 19) is wired up"
  value       = aws_cloudfront_distribution.this.domain_name
}
