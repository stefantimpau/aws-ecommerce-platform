locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# A single monthly cost budget covering the WHOLE ACCOUNT, not just this
# project's tagged resources. Deliberate — AWS Budgets can filter by cost
# allocation tag, but tag-based filtering only works retroactively once
# tags are activated as cost allocation tags in Billing preferences (a
# manual console step Terraform can't do, and one that only starts
# collecting data from the activation date forward). An account-level
# budget catches everything from day one with no extra setup, which
# matters more for a guardrail than precision — this account has nothing
# else running in it. Three thresholds (50/80/100% of the limit) instead
# of one gives an early warning before an actual overspend.
# ---------------------------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.alert_thresholds_percent
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.notification_email]
    }
  }

  # A separate FORECASTED alert at 100% — catches "you're on track to
  # blow the budget this month" days before ACTUAL spend crosses the
  # line, rather than only finding out after the fact.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notification_email]
  }
}
