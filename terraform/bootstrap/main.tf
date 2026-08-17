# One-time bootstrap: creates the S3 bucket that holds Terraform remote
# state for terraform/environments/dev, once CI/CD needs to run
# `terraform apply` from an ephemeral GitHub Actions runner rather than
# only ever from a laptop with a persistent local state file.
#
# This has to live in its own separately-applied config with its own
# (local) state — a backend can't be created by the same state it's
# meant to hold. Run this once, by hand, before switching on the S3
# backend block in terraform/environments/dev/versions.tf.
#
# Usage:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#   # then follow the migration steps in terraform/environments/dev/versions.tf

terraform {
  required_version = ">= 1.10.0" # for native S3 state locking (use_lockfile) — no DynamoDB table needed

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "state" {
  bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"

  # Deliberately NOT force_destroy — this bucket holds the only copy of
  # Terraform state for the whole project; an accidental `terraform
  # destroy` in the wrong directory should not be able to take it out.
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # recover a previous state version if an apply ever corrupts it
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}
