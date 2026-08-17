project     = "aws-ecommerce-platform"
environment = "dev"
aws_region  = "eu-west-2"
azs         = ["eu-west-2a", "eu-west-2b"]


vpc_cidr                  = "10.20.0.0/16"
public_subnet_cidrs       = ["10.20.0.0/24", "10.20.1.0/24"]
private_app_subnet_cidrs  = ["10.20.10.0/24", "10.20.11.0/24"]
private_data_subnet_cidrs = ["10.20.20.0/24", "10.20.21.0/24"]

enable_github_oidc = true

github_repo = "stefantimpau/aws-ecommerce-platform"

single_nat_gateway = true

# Dedicated public AWS-portfolio contact address (already listed on the
# user's site/CV for this purpose) — safe to commit, unlike a personal
# inbox. See variables.tf for why this one has a default at all.
notification_email = "contact@stefantimpau.com"

# ECR repos here use immutable tags — this can never be reused once
# pushed. Bump it (v3, v4, ...) each time scripts/build-and-push.sh runs
# with a new tag, then re-apply.
image_tag = "v2"
