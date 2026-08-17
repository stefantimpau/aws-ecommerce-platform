variable "project" {
  description = "Project name"
  type        = string
  default     = "aws-ecommerce-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for all regional resources"
  type        = string
  default     = "eu-west-2"
}

variable "azs" {
  description = "Availability zones to use (2)"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_app_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "private_data_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.20.0/24", "10.20.21.0/24"]
}

variable "single_nat_gateway" {
  description = "Use one NAT Gateway instead of one per AZ (cost trade-off)"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address subscribed to the order-events SNS topic. Defaults to a dedicated public contact address the user already lists on their site/CV for exactly this purpose — deliberately NOT a personal inbox, which is why a default is acceptable here despite this repo being public. If this is ever pointed at a non-public address, remove the default and pass it at apply time instead (-var or TF_VAR_notification_email)."
  type        = string
  default     = "contact@stefantimpau.com"
}

variable "image_tag" {
  description = "Tag (in every ECR repo) to deploy for all four services. ECR repos here use immutable tags, so this can never be reused once pushed — bump it (e.g. a new git SHA or v3, v4...) each time scripts/build-and-push.sh runs, then re-apply so the ECS task definitions pick up the new image."
  type        = string
  default     = "v2"
}

variable "enable_github_oidc" {
  description = "Whether to create the GitHub Actions OIDC deploy role (terraform/modules/github-oidc). False by default — flip to true only after the repo exists on GitHub and github_repo below is set to its real \"owner/repo\", otherwise the trust policy would (harmlessly, but pointlessly) scope itself to a repo that doesn't exist yet."
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI/CD deploy role, as \"owner/repo\". Only used when enable_github_oidc = true. Never set this to a wildcard or another account's repo."
  type        = string
  default     = "REPLACE_ME/aws-ecommerce-platform"
}

variable "github_oidc_sub_prefix" {
  description = <<-EOT
    Passthrough to module.github_oidc's variable of the same name — overrides
    the OIDC trust policy's expected "repo:..." subject prefix for accounts
    where GitHub doesn't send the plain "repo:<owner>/<repo>" slug. Find the
    real value with:
      gh api /repos/<owner>/<repo>/actions/oidc/customization/sub
    and copy its "sub_claim_prefix" field here. Leave unset (null) to use
    the classic "repo:<github_repo>" format.
  EOT
  type        = string
  default     = null
}
