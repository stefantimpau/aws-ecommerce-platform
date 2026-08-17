output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "product_task_role_arn" {
  value = aws_iam_role.product_task.arn
}

output "cart_task_role_arn" {
  value = aws_iam_role.cart_task.arn
}

output "user_task_role_arn" {
  value = aws_iam_role.user_task.arn
}

output "order_task_role_arn" {
  value = aws_iam_role.order_task.arn
}
