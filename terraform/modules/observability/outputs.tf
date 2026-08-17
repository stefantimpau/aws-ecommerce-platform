output "ops_alerts_topic_arn" {
  value = aws_sns_topic.ops_alerts.arn
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}

output "dashboard_url" {
  description = "Direct console URL to the dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.this.dashboard_name}"
}
