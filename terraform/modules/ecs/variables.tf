variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "execution_role_arn" {
  description = "Shared ECS task execution role (ECR pull, logs, DB-password secret injection)"
  type        = string
}

variable "product_task_role_arn" {
  type = string
}

variable "cart_task_role_arn" {
  type = string
}

variable "user_task_role_arn" {
  type = string
}

variable "order_task_role_arn" {
  type = string
}

variable "ecr_repository_urls" {
  description = "Map of service name (product/cart/user/order) -> ECR repository URL"
  type        = map(string)
}

variable "image_tag" {
  description = "Image tag to deploy — set to a specific git SHA/version once scripts/build-and-push.sh has pushed one; defaults to 'latest' for the very first apply"
  type        = string
  default     = "latest"
}

variable "container_ports" {
  type = map(number)
  default = {
    product = 8081
    cart    = 8082
    user    = 8083
    order   = 8084
  }
}

variable "task_cpu" {
  description = "Fargate task vCPU units — 256 (.25 vCPU) is the smallest Fargate size, plenty for a portfolio workload"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory (MB) — 512 is the minimum paired with 256 CPU units"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  type    = number
  default = 14
}

# Non-secret runtime config, already created by the ssm-config/rds modules
variable "dynamodb_products_table" {
  type = string
}

variable "dynamodb_cart_table" {
  type = string
}

variable "cognito_user_pool_id" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_port" {
  type = number
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password_ssm_param_arn" {
  description = "Injected as a container secret, not a plain environment variable"
  type        = string
}

variable "order_events_topic_arn" {
  description = "SNS topic the order-service publishes order-placed events to"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Subnets the ECS tasks run in (private-app tier, both AZs)"
  type        = list(string)
}

variable "ecs_tasks_sg_id" {
  description = "Security group for ECS tasks (accepts traffic from the internal ALB only, once it exists)"
  type        = string
}

variable "desired_count" {
  description = "Desired task count per service — 1 for a portfolio workload, no need for redundancy"
  type        = number
  default     = 1
}

variable "attach_load_balancer" {
  description = "Whether to attach services to the internal ALB target groups. False until build step 15 — this module can create the services running standalone (no LB) first, per the project's build order, and the ALB gets wired in without recreating the services."
  type        = bool
  default     = false
}

variable "target_group_arns" {
  description = "Map of service name -> target group ARN. Only used when attach_load_balancer = true (build step 15)."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
