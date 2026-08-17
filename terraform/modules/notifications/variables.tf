variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "notification_email" {
  description = "Email address for order-event notifications. Deliberately has NO default and is never written to terraform.tfvars (that file is committed to a public GitHub repo) — pass it at apply time with -var or TF_VAR_notification_email instead."
  type        = string
}

variable "shipping_queue_max_receive_count" {
  description = "How many times a message can be received before it's moved to the dead-letter queue"
  type        = number
  default     = 5
}

variable "tags" {
  type    = map(string)
  default = {}
}
