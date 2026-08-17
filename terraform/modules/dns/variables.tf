variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "root_domain" {
  description = "Existing Route 53 hosted zone's domain — this module looks it up, it does NOT create a new zone (the user already manages this domain in Route 53)"
  type        = string
  default     = "stefantimpau.com"
}

variable "frontend_subdomain" {
  description = "Subdomain for the CloudFront-served frontend (build step 19 wires this up as CloudFront's alternate domain name)"
  type        = string
  default     = "shop.stefantimpau.com"
}

variable "api_subdomain" {
  description = "Subdomain for the API Gateway custom domain (build step 19)"
  type        = string
  default     = "api.shop.stefantimpau.com"
}

variable "tags" {
  type    = map(string)
  default = {}
}
