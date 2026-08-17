terraform {
  required_version = ">= 1.10.0" # for native S3 state locking (use_lockfile) once the S3 backend below is switched on

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Local backend by default (portfolio project, run by hand from a laptop
  # most of the time) — but the GitHub Actions deploy workflow
  # (.github/workflows/deploy.yml) is an ephemeral runner with no local
  # disk to persist state on, so it needs a real remote backend. To switch
  # this on:
  #
  #   1. cd terraform/bootstrap && terraform init && terraform apply
  #      (one-time — creates the S3 state bucket; see that directory's
  #      main.tf for why it can't live in this same state)
  #   2. Uncomment the backend block below, filling in the bucket name
  #      from that apply's `state_bucket_name` output.
  #   3. terraform init -migrate-state
  #      (moves the existing local terraform.tfstate into S3 — answer
  #      "yes" when prompted; the local state file is left in place too,
  #      as a backup, until you're sure the migration worked)
  #
  # use_lockfile uses S3's own conditional-write locking (Terraform
  # >=1.10) instead of a separate DynamoDB lock table — one less resource
  # to create and pay for.

  backend "s3" {
    bucket       = "aws-ecommerce-platform-tfstate-264502359266"
    key          = "environments/dev/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Required for the dns module's CloudFront certificate — ACM certs used by
# CloudFront must be requested in us-east-1 no matter what region
# everything else runs in.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
