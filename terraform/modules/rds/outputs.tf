output "db_instance_id" {
  # Deliberately `.identifier`, NOT `.id` — for this provider version,
  # aws_db_instance's `id` attribute resolves to RDS's internal DbiResourceId
  # (looks like "db-XXXXXXXXXXXX", visible in `terraform apply` logs as
  # this resource's tracked id), not the instance identifier string.
  # CloudWatch's AWS/RDS metrics use DBInstanceIdentifier as their
  # dimension — that's this instance's `identifier` argument
  # ("aws-ecommerce-platform-dev-orders-db"), a completely different
  # value from `.id`. Every consumer of this output (both RDS alarms in
  # terraform/modules/observability, plus its three RDS dashboard
  # widgets) was silently pointed at a dimension value CloudWatch has no
  # data under — caught because the dashboard's RDS panels showed "No
  # data available" despite the RDS console's own Monitoring tab (and a
  # raw `aws cloudwatch get-metric-statistics` CLI call) showing real
  # CPUUtilization data all along. See the README's Incident Notes.
  value = aws_db_instance.this.identifier
}

output "db_endpoint" {
  description = "host:port"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "host only"
  value       = aws_db_instance.this.address
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_username" {
  value = aws_db_instance.this.username
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_password_ssm_param_name" {
  value = aws_ssm_parameter.db_password.name
}

output "db_password_ssm_param_arn" {
  value = aws_ssm_parameter.db_password.arn
}
