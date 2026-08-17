output "deploy_role_arn" {
  description = "Set this as the AWS_DEPLOY_ROLE_ARN repo variable in GitHub (Settings -> Secrets and variables -> Actions -> Variables) for .github/workflows/deploy.yml to assume."
  value       = aws_iam_role.deploy.arn
}
