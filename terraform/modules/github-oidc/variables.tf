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
  description = "GitHub repo allowed to assume this role, as \"owner/repo\" (e.g. \"stefantimpau/aws-ecommerce-platform\"). Used to build the default OIDC trust policy subject prefix (\"repo:<github_repo>\") when github_oidc_sub_prefix is not set. Never leave this as a wildcard."
  type        = string
}

variable "github_oidc_sub_prefix" {
  description = <<-EOT
    Overrides the "repo:..." prefix matched in the OIDC trust policy's sub
    claim condition, for accounts where GitHub's actual token subject isn't
    the plain "repo:<owner>/<repo>" slug. Many GitHub accounts now default
    to an ID-suffixed subject (e.g. "repo:owner@<owner_id>/repo@<repo_id>")
    rather than the classic slug-only format, and using the wrong one means
    every AssumeRoleWithWebIdentity call is silently denied even though the
    trust policy "looks" correct.

    Check what this account/repo actually sends before assuming either
    format:
      gh api /repos/<owner>/<repo>/actions/oidc/customization/sub
    and copy its "sub_claim_prefix" value here verbatim (do not include the
    trailing ":ref:..." — that part is added automatically below).

    Defaults to "repo:<github_repo>" (the classic format) when unset.
  EOT
  type        = string
  default     = null
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
