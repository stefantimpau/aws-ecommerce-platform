variable "project" {
  description = "Project name, used as a prefix/tag on all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across (exactly 2 expected)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per AZ"
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for the private application subnets (ECS tasks), one per AZ"
  type        = list(string)
}

variable "private_data_subnet_cidrs" {
  description = "CIDR blocks for the private data subnets (RDS), one per AZ"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (in AZ 0) for both private subnets instead of one per AZ. Cheaper, less resilient — see docs/adr for the trade-off writeup."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
