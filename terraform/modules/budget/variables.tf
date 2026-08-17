variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "monthly_limit_usd" {
  description = "Alert threshold, not a hard spending cap — AWS Budgets can notify but can't block spend on its own. Sized for a small always-on demo stack (NAT gateway, RDS, ALB, a handful of Fargate tasks) run for a few days at a time, with headroom for a mistake like forgetting to tear down over a weekend."
  type        = number
  default     = 15
}

variable "alert_thresholds_percent" {
  description = "ACTUAL-spend thresholds (% of monthly_limit_usd) that each trigger a separate email — an early warning ladder rather than a single all-or-nothing alert."
  type        = list(number)
  default     = [50, 80, 100]
}

variable "notification_email" {
  description = "Where budget alert emails go. No default — must be supplied with -var or TF_VAR_notification_email, same as var.notification_email in the root module, so it never lands in a committed file in this public repo."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
