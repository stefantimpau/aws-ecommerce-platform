output "cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_arns" {
  description = "ARNs of the four ECS services, keyed by service name — for scoping IAM policies (e.g. terraform/modules/github-oidc) to ecs:UpdateService on exactly these services."
  value       = { for k, v in aws_ecs_service.this : k => v.id }
}

output "task_definition_family_arns" {
  description = "Wildcarded family ARNs (…:task-definition/<family>:*) for scoping ecs:DescribeTaskDefinition / ecs:DeregisterTaskDefinition without granting access to every task definition in the account."
  value       = { for k, v in aws_ecs_task_definition.this : k => "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/${v.family}:*" }
}

output "task_definition_arns" {
  value = { for k, v in aws_ecs_task_definition.this : k => v.arn }
}

output "task_definition_families" {
  value = { for k, v in aws_ecs_task_definition.this : k => v.family }
}

output "log_group_names" {
  value = { for k, v in aws_cloudwatch_log_group.this : k => v.name }
}

output "service_names" {
  value = { for k, v in aws_ecs_service.this : k => v.name }
}
