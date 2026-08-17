locals {
  name = "${var.project}-${var.environment}"
  common_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# Repo names follow the "${project}-${environment}-<service>" convention
# that terraform/modules/iam's execution-role ECR permissions already
# assume (see local.ecr_repo_arn_pattern there) — keep this in sync if
# either naming scheme changes.
resource "aws_ecr_repository" "this" {
  for_each = toset(var.services)

  name                 = "${local.name}-${each.value}"
  image_tag_mutability = "IMMUTABLE" # a given tag (e.g. a git SHA) can never be silently overwritten

  # Portfolio project torn down between demo sessions (see
  # scripts/teardown/destroy.sh) — without this, `terraform destroy`
  # fails on every repo that still has pushed images in it (all four,
  # after scripts/build-and-push.sh has ever run) with
  # RepositoryNotEmptyException.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name}-${each.value}"
    Service = each.value
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent ${var.max_tagged_images} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_tagged_images
        }
        action = { type = "expire" }
      }
    ]
  })
}
