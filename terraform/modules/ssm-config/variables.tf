variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "cognito_user_pool_id" {
  type = string
}

variable "cognito_user_pool_client_id" {
  type = string
}

variable "cognito_issuer_url" {
  type = string
}

variable "dynamodb_products_table" {
  type = string
}

variable "dynamodb_cart_table" {
  type = string
}

variable "frontend_bucket_name" {
  type = string
}

variable "images_bucket_name" {
  type = string
}

variable "cloudfront_domain_name" {
  type = string
}

variable "api_base_url" {
  description = "API Gateway invoke URL — the frontend's backend base URL. Empty until build step 16/17 (API Gateway) exists; the frontend build (step 18) reads this before it can be wired up for real."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
