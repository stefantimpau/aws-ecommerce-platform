locals {
  name = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)

  # SSM Parameter Store rejects any parameter path starting with the
  # reserved "aws" prefix. var.project is "aws-ecommerce-platform", so
  # strip the leading "aws-" before building the path.
  ssm_prefix = "/${replace(var.project, "aws-", "")}/${var.environment}"
}

# ---------------------------------------------------------------------------
# Master password — generated, never hardcoded, stored as an SSM SecureString
# (this pulls build-order step 6's "DB password as SecureString" forward
# into this module since RDS needs credentials at creation time; the rest
# of the SSM parameters — region, DB host, etc. — are set up separately).
# ---------------------------------------------------------------------------

resource "random_password" "db" {
  length  = 24
  special = true
  # RDS Postgres rejects '/', '@', '"', and space in the password.
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_ssm_parameter" "db_password" {
  name        = "${local.ssm_prefix}/db/password"
  description = "RDS Postgres master password"
  type        = "SecureString"
  value       = random_password.db.result

  tags = local.common_tags
}

resource "aws_ssm_parameter" "db_host" {
  name        = "${local.ssm_prefix}/db/host"
  description = "RDS Postgres endpoint (host only, no port)"
  type        = "String"
  value       = aws_db_instance.this.address

  tags = local.common_tags
}

resource "aws_ssm_parameter" "db_name" {
  name  = "${local.ssm_prefix}/db/name"
  type  = "String"
  value = var.db_name

  tags = local.common_tags
}

resource "aws_ssm_parameter" "db_username" {
  name  = "${local.ssm_prefix}/db/username"
  type  = "String"
  value = var.db_username

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# DB subnet group — private-data subnets, both AZs
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db-subnet-group"
  subnet_ids = var.private_data_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name}-db-subnet-group"
  })
}

# ---------------------------------------------------------------------------
# RDS Postgres — single-AZ, to control cost (multi-AZ doubles instance cost
# for a portfolio project with no real availability requirement)
# ---------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = "${local.name}-orders-db"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.vpc_security_group_ids

  multi_az            = false
  publicly_accessible = false

  backup_retention_period = var.backup_retention_days
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-orders-db"
    Tier = "data"
  })
}
