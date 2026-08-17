locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# Products table — catalog data. Read-heavy, simple key-value/lookup access
# pattern (get by ID, or scan/query by category via a GSI) — a good fit for
# DynamoDB over a relational table. See docs/adr/0002 for the DynamoDB vs
# RDS split rationale.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "products" {
  name         = "${local.name}-products"
  billing_mode = "PAY_PER_REQUEST" # no capacity planning needed; cost scales to zero when idle
  hash_key     = "productId"

  attribute {
    name = "productId"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  global_secondary_index {
    name            = "category-index"
    hash_key        = "category"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = false # portfolio project — skip PITR to avoid extra cost; would enable for a real production table
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-products"
  })
}

# ---------------------------------------------------------------------------
# Cart table — per-user, ephemeral, high write volume relative to size.
# TTL is used to auto-expire abandoned carts instead of a cleanup job.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "cart" {
  name         = "${local.name}-cart"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "productId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "productId"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-cart"
  })
}
