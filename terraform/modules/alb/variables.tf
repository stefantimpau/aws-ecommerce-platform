variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets the ALB's ENIs land in — private-app tier, both AZs. Internal ALB, never a public subnet."
  type        = list(string)
}

variable "security_group_id" {
  description = "The ALB's security group (terraform/modules/security-groups aws_security_group.alb) — accepts HTTP from the VPC CIDR only"
  type        = string
}

variable "container_ports" {
  description = "Map of service name -> container port, same map the ecs module uses — one target group per entry"
  type        = map(number)
  default = {
    product = 8081
    cart    = 8082
    user    = 8083
    order   = 8084
  }
}

variable "path_patterns" {
  description = "Map of service name -> listener rule path pattern(s). Drives which service each request routes to; kept in sync with the API Gateway routes added in build step 17."
  type        = map(list(string))
  default = {
    product = ["/products", "/products/*"]
    cart    = ["/cart", "/cart/*"]
    user    = ["/users", "/users/*"]
    order   = ["/orders", "/orders/*"]
  }
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "attach_web_acl" {
  description = "Whether to associate a Web ACL with this ALB (build step 20). A plain bool rather than testing web_acl_arn != \"\" — that ARN comes from module.waf, a resource created in the SAME apply, so its value is unknown at plan time and can't drive a count decision (Terraform's \"Invalid count argument\" error — hit once already on the apigateway module's version of this). This flag is a literal the caller sets, so it's always known."
  type        = bool
  default     = false
}

variable "web_acl_arn" {
  description = "ARN of a REGIONAL-scope WAFv2 Web ACL (build step 20) to associate with this ALB. Only used when attach_web_acl is true."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
