variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets the VPC Link's ENIs land in — private-app tier, both AZs"
  type        = list(string)
}

variable "security_group_id" {
  description = "The VPC Link's security group (terraform/modules/security-groups aws_security_group.vpc_link)"
  type        = string
}

variable "alb_listener_arn" {
  description = "The internal ALB's HTTP listener ARN — every route's integration target. Path-based routing to the right service happens on the ALB side (terraform/modules/alb listener rules), so one integration serves every route here."
  type        = string
}

variable "cognito_issuer_url" {
  type = string
}

variable "cognito_user_pool_client_id" {
  description = "Expected audience (aud claim) for the JWT authorizer"
  type        = string
}

variable "cors_allow_origins" {
  description = "Origins allowed to call this API from a browser — the CloudFront frontend domain(s). Never \"*\" alongside allow_credentials."
  type        = list(string)
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "custom_domain_name" {
  description = "API Gateway custom domain — build step 19. Empty means \"no custom domain yet, use the default execute-api.* URL\"."
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "Regional (same-region as the API) ACM cert covering custom_domain_name — required if custom_domain_name is set."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
