output "order_events_topic_arn" {
  value = aws_sns_topic.order_events.arn
}

output "shipping_queue_arn" {
  value = aws_sqs_queue.shipping.arn
}

output "shipping_queue_url" {
  value = aws_sqs_queue.shipping.id
}

output "shipping_dlq_arn" {
  value = aws_sqs_queue.shipping_dlq.arn
}
