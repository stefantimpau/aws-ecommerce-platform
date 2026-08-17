locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# SNS topic — the order-service publishes here once an order is placed
# (see the TODO in services/order-service/src/index.js, closed out by this
# step). Fans out to two subscribers: an email address for a human-visible
# notification, and the shipping SQS queue for the eventual fulfillment
# side of the app.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "order_events" {
  name = "${local.name}-order-events"

  tags = merge(local.common_tags, {
    Name = "${local.name}-order-events"
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.order_events.arn
  protocol  = "email"
  endpoint  = var.notification_email
  # Email subscriptions require manual confirmation via a link AWS sends to
  # the address above — Terraform can't complete that step for you.
}

# ---------------------------------------------------------------------------
# SQS queue — shipping side of order fulfillment. Has its own dead-letter
# queue so a message that repeatedly fails processing doesn't loop forever
# or get silently dropped; it lands somewhere visible instead.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "shipping_dlq" {
  name                      = "${local.name}-shipping-dlq"
  message_retention_seconds = 1209600 # 14 days — max retention, gives time to notice and investigate

  tags = merge(local.common_tags, {
    Name = "${local.name}-shipping-dlq"
  })
}

resource "aws_sqs_queue" "shipping" {
  name                       = "${local.name}-shipping"
  message_retention_seconds = 345600 # 4 days
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.shipping_dlq.arn
    maxReceiveCount      = var.shipping_queue_max_receive_count
  })

  tags = merge(local.common_tags, {
    Name = "${local.name}-shipping"
  })
}

# Only the order-events SNS topic (this specific one) may deliver messages
# into the shipping queue — scoped by source ARN, not open to any SNS
# topic in the account.
data "aws_iam_policy_document" "shipping_queue_policy" {
  statement {
    sid       = "AllowSnsOrderEventsOnly"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.shipping.arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.order_events.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "shipping" {
  queue_url = aws_sqs_queue.shipping.id
  policy    = data.aws_iam_policy_document.shipping_queue_policy.json
}

resource "aws_sns_topic_subscription" "sqs" {
  topic_arn = aws_sns_topic.order_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.shipping.arn
}
