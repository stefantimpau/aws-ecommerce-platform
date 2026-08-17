locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# Ops alerts topic — deliberately SEPARATE from the order-events topic
# (terraform/modules/notifications). That topic is customer/business
# events (an order was placed); this one is infrastructure health (RDS
# running low on disk, a service losing its tasks). Different audiences,
# different urgency, different channel — even though both currently land
# in the same inbox, keeping them as distinct SNS topics means a future
# on-call rotation or PagerDuty integration only has to subscribe to this
# one, not filter order confirmations out of it.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "ops_alerts" {
  name = "${local.name}-ops-alerts"

  tags = merge(local.common_tags, {
    Name = "${local.name}-ops-alerts"
  })
}

resource "aws_sns_topic_subscription" "ops_alerts_email" {
  topic_arn = aws_sns_topic.ops_alerts.arn
  protocol  = "email"
  endpoint  = var.ops_alert_email
}

# ---------------------------------------------------------------------------
# Alarms
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${local.name}-rds-cpu-high"
  alarm_description   = "RDS Postgres CPU above ${var.rds_cpu_alarm_threshold}% for 10 minutes"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rds_cpu_alarm_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${local.name}-rds-storage-low"
  alarm_description   = "RDS Postgres free storage below ${var.rds_free_storage_threshold_bytes} bytes"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = var.rds_free_storage_threshold_bytes
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]

  tags = local.common_tags
}

# One "service lost its tasks" alarm per service, using ECS Container
# Insights (enabled on the cluster in the ecs module). Missing data is
# treated as breaching here — deliberately different from the RDS alarms
# above — because a service with zero data points for RunningTaskCount is
# itself a signal something's wrong (the service or the cluster stopped
# reporting), not something to silently ignore.
resource "aws_cloudwatch_metric_alarm" "service_tasks_missing" {
  for_each = var.ecs_service_names

  alarm_name          = "${local.name}-${each.key}-tasks-missing"
  alarm_description   = "${each.key}-service has fewer than 1 running task"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = each.value
  }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.ops_alerts.arn]
  ok_actions    = [aws_sns_topic.ops_alerts.arn]

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Dashboard — one view across the app tier, data tier, and the one NAT
# Gateway (its data-processing charge is the easiest thing in this stack
# to accidentally run up, worth keeping an eye on even outside an alarm).
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${local.name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${local.name} — build order step 13 dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "ECS — CPU utilized by service"
          region = var.aws_region
          view   = "timeSeries"
          stacked = false
          metrics = [
            for key, svc in var.ecs_service_names :
            ["ECS/ContainerInsights", "CpuUtilized", "ClusterName", var.ecs_cluster_name, "ServiceName", svc, { label = key }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "ECS — memory utilized by service"
          region = var.aws_region
          view   = "timeSeries"
          stacked = false
          metrics = [
            for key, svc in var.ecs_service_names :
            ["ECS/ContainerInsights", "MemoryUtilized", "ClusterName", var.ecs_cluster_name, "ServiceName", svc, { label = key }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "RDS — CPU utilization"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "RDS — database connections"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "RDS — free storage space"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB — consumed capacity"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_products_table, { label = "products read" }],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.dynamodb_products_table, { label = "products write" }],
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_cart_table, { label = "cart read" }],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.dynamodb_cart_table, { label = "cart write" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "NAT Gateway — data processed (cost driver to watch)"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/NATGateway", "BytesOutToDestination", "NatGatewayId", var.nat_gateway_id, { label = "out to internet" }],
            ["AWS/NATGateway", "BytesOutToSource", "NatGatewayId", var.nat_gateway_id, { label = "out to VPC" }]
          ]
        }
      }
    ]
  })
}
