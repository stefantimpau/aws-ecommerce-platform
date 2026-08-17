variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "create_oidc_provider" {
  description = "Whether to create the token.actions.githubusercontent.com OIDC provider. An AWS account can only have one provider per URL — set this to false (and point role_oidc_provider_arn-less trust policy at the existing one, via a data source) if a prior project in this account already created it."
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "GitHub repo allowed to assume this role, as \"owner/repo\" (e.g. \"stefantimpau/aws-ecommerce-platform\"). Scopes the OIDC trust policy so only workflow runs from this exact repo can assume the deploy role — never leave this as a wildcard."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ARNs of the four service ECR repos — the deploy role can only push to these, nothing else in ECR."
  type        = list(string)
}

variable "ecs_cluster_arn" {
  type = string
}

variable "ecs_service_arns" {
  description = "ARNs of the four ECS services — scopes ecs:UpdateService so the deploy role can only touch this project's services."
  type        = list(string)
}

variable "ecs_task_definition_family_arns" {
  description = "Wildcarded task-definition family ARNs (…:task-definition/<family>:*), one per service — scopes Describe/Deregister. RegisterTaskDefinition itself has no resource-level permissions in IAM (AWS limitation), so that action is granted on \"*\" regardless."
  type        = list(string)
}

variable "passable_role_arns" {
  description = "IAM roles the deploy role must be able to iam:PassRole when registering a new task definition revision — the ECS task execution role plus all four task roles."
  type        = list(string)
}

variable "state_bucket_arn" {
  description = "ARN of the S3 bucket holding this project's Terraform state (terraform/bootstrap)."
  type        = string
}

variable "frontend_bucket_arn" {
  type = string
}

variable "cloudfront_distribution_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
