variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "callback_urls" {
  description = "Allowed OAuth redirect URLs for the app client (add the CloudFront/custom domain once known — build step 18/19)"
  type        = list(string)
  default     = ["http://localhost:3000"]
}

variable "logout_urls" {
  description = "Allowed post-logout redirect URLs"
  type        = list(string)
  default     = ["http://localhost:3000"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
