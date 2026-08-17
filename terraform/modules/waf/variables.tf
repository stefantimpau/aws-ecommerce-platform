variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "rate_limit" {
  description = "Max requests from a single IP per 5-minute window before the CloudFront WAF blocks it"
  type        = number
  default     = 2000
}

variable "api_rate_limit" {
  description = "Max requests from a single IP per 5-minute window before the API WAF blocks it — lower than the CloudFront limit since there's no CDN cache absorbing repeat hits here"
  type        = number
  default     = 1000
}

variable "tags" {
  type    = map(string)
  default = {}
}
