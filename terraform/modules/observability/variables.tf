variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "ops_alert_email" {
  description = "Email for infrastructure alarms (deliberately a separate SNS topic from order-events — a DB running low on storage and a customer order confirmation shouldn't share a notification channel)"
  type        = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_names" {
  description = "Map of service key (product/cart/user/order) -> ECS service name"
  type        = map(string)
}

variable "db_instance_id" {
  type = string
}

variable "nat_gateway_id" {
  type = string
}

variable "dynamodb_products_table" {
  type = string
}

variable "dynamodb_cart_table" {
  type = string
}

variable "rds_cpu_alarm_threshold" {
  type    = number
  default = 80
}

variable "rds_free_storage_threshold_bytes" {
  description = "Alarm when RDS free storage drops below this many bytes"
  type        = number
  default     = 2147483648 # 2 GiB
}

variable "tags" {
  type    = map(string)
  default = {}
}
