variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "products_table_arn" {
  type = string
}

variable "cart_table_arn" {
  type = string
}

variable "cognito_user_pool_arn" {
  type = string
}

variable "db_password_ssm_param_arn" {
  description = "ARN of the RDS master password SecureString param — the only true secret the execution role injects into containers"
  type        = string
}

variable "order_events_topic_arn" {
  description = "ARN of the SNS order-events topic — the order task role gets sns:Publish scoped to exactly this ARN"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
