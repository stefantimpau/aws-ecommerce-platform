variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_data_subnet_ids" {
  description = "Subnet IDs for the DB subnet group (private-data tier, both AZs)"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "Security groups to attach to the RDS instance (the rds-sg from the security-groups module)"
  type        = list(string)
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "ecommerce"
}

variable "db_username" {
  description = "Master username"
  type        = string
  default     = "ecommerce_admin"
}

variable "engine_version" {
  # Major-version-only ("16" rather than e.g. "16.4") lets RDS resolve to
  # whatever minor version is currently available in this region, instead
  # of pinning a specific minor that AWS can (and does) retire over time.
  description = "Postgres engine version"
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class — smallest burstable class, adequate for a portfolio/demo workload"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Storage in GB"
  type        = number
  default     = 20
}

variable "backup_retention_days" {
  description = "Automated backup retention. Kept short to limit storage cost on a project that gets torn down between sessions."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Set true only if this needs to survive accidental `terraform destroy` — left false so the documented teardown script can remove it cleanly."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
