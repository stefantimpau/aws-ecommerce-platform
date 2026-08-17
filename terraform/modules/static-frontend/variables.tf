variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "price_class" {
  description = "CloudFront price class — PriceClass_100 (US/Canada/Europe only) keeps cost down for a portfolio project with no real global audience"
  type        = string
  default     = "PriceClass_100"
}

variable "aliases" {
  description = "Alternate domain name(s) for the CloudFront distribution — build step 19. Empty means \"no custom domain yet, use the default *.cloudfront.net cert\"."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "us-east-1 ACM cert covering `aliases` — required if aliases is non-empty (CloudFront only accepts certs from us-east-1, regardless of the distribution's edge locations)."
  type        = string
  default     = ""
}

variable "web_acl_id" {
  description = "ARN of a CLOUDFRONT-scope WAFv2 Web ACL (build step 20). Empty means no WAF attached yet — CloudFront treats an empty string the same as omitting the argument."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
