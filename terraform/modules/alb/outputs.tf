output "alb_arn" {
  value = aws_lb.internal.arn
}

output "alb_dns_name" {
  description = "Internal DNS name — only resolvable/reachable from within the VPC. Used as the API Gateway VPC Link's target in build step 16."
  value       = aws_lb.internal.dns_name
}

output "alb_listener_arn" {
  value = aws_lb_listener.http.arn
}

output "target_group_arns" {
  description = "Map of service name -> target group ARN, passed to the ecs module's target_group_arns in build step 15"
  value       = { for k, v in aws_lb_target_group.this : k => v.arn }
}
