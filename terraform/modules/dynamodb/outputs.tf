output "products_table_name" {
  value = aws_dynamodb_table.products.name
}

output "products_table_arn" {
  value = aws_dynamodb_table.products.arn
}

output "cart_table_name" {
  value = aws_dynamodb_table.cart.name
}

output "cart_table_arn" {
  value = aws_dynamodb_table.cart.arn
}
