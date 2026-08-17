variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "services" {
  description = "Service names, one ECR repo per entry (e.g. [\"product\", \"cart\", \"user\", \"order\"])"
  type        = list(string)
}

variable "untagged_image_expiry_days" {
  description = "Expire untagged images after this many days — keeps storage cost down without touching tagged (deployed) images"
  type        = number
  default     = 7
}

variable "max_tagged_images" {
  description = "Keep only the most recent N tagged images per repo"
  type        = number
  default     = 10
}

variable "tags" {
  type    = map(string)
  default = {}
}
