variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "VPC to create security groups in"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block, used for a couple of intra-VPC rules (e.g. health checks)"
  type        = string
}

variable "container_ports" {
  description = "Map of service name -> container port, one SG ingress rule per service (ALB -> ECS tasks)"
  type        = map(number)
  default = {
    product = 8081
    cart    = 8082
    user    = 8083
    order   = 8084
  }
}

variable "db_port" {
  description = "RDS Postgres port"
  type        = number
  default     = 5432
}

variable "tags" {
  type    = map(string)
  default = {}
}
