#!/usr/bin/env bash
# Tear down every resource this project created, for cost control between
# demo sessions — a small always-on stack (NAT gateway, RDS, ALB, ECS
# tasks, WAF Web ACLs) adds up if left running unattended (see
# terraform/modules/budget for the account-level spending alert that
# backs this up).
#
# This is a THIN wrapper over `terraform destroy` — almost everything it
# needs was already handled by making the resources themselves
# destroy-friendly (aws_s3_bucket force_destroy, aws_ecr_repository
# force_delete, aws_db_instance skip_final_snapshot/deletion_protection =
# false — see each module). What this script adds on top:
#   - a real confirmation prompt naming the AWS account, since this is
#     irreversible
#   - a reminder that CloudFront distribution deletion is slow (AWS has
#     to disable it globally first) so `terraform destroy` can sit for
#     15-45 minutes on that one resource with no visible progress
#   - cleaning up the frontend's generated .env.production so a stale
#     build config isn't left behind pointing at now-deleted resources
#
# Run this locally (not the Cowork cloud sandbox) — it needs your AWS CLI
# credentials for account 264502359266 and terraform on PATH.
#
# Usage: ./scripts/teardown/destroy.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/environments/dev"
ACCOUNT_ID="264502359266"

echo "=============================================================="
echo " TEARDOWN: aws-ecommerce-platform (dev)"
echo " AWS account: ${ACCOUNT_ID}"
echo "=============================================================="
echo ""
echo "This will destroy EVERY resource currently managed by Terraform in"
echo "${TF_DIR},"
echo "including the RDS database (no final snapshot — see"
echo "terraform/modules/rds's skip_final_snapshot default) and both S3"
echo "buckets (force_destroy — any objects in them, including product"
echo "images and the deployed frontend build, are deleted along with the"
echo "buckets)."
echo ""
echo "This is NOT reversible."
echo ""
read -r -p "Type the AWS account ID (${ACCOUNT_ID}) to confirm: " CONFIRM_ACCOUNT
if [[ "${CONFIRM_ACCOUNT}" != "${ACCOUNT_ID}" ]]; then
  echo "Account ID didn't match — aborting, nothing was destroyed."
  exit 1
fi

echo ""
echo "Confirmed. Running terraform plan -destroy first so you can see"
echo "exactly what's about to go..."
echo ""
terraform -chdir="${TF_DIR}" plan -destroy

echo ""
read -r -p "Proceed with 'terraform destroy' using the plan above? [y/N] " CONFIRM_DESTROY
if [[ "${CONFIRM_DESTROY}" != "y" && "${CONFIRM_DESTROY}" != "Y" ]]; then
  echo "Aborting — nothing was destroyed."
  exit 1
fi

echo ""
echo "Destroying. The CloudFront distribution (module.static_frontend) is"
echo "the slowest part of this — AWS has to disable it globally before"
echo "Terraform can delete it, which can take 15-45 minutes with no"
echo "visible progress in the meantime. Everything else is fast."
echo ""
terraform -chdir="${TF_DIR}" destroy

echo ""
echo "Cleaning up local generated frontend config (.env.production) —"
echo "it points at resources that no longer exist."
rm -f "${ROOT_DIR}/frontend/.env.production"

echo ""
echo "Done. Re-run 'terraform apply' (and scripts/build-and-push.sh +"
echo "scripts/deploy-frontend.sh) from a clean state to bring it back up"
echo "for the next demo session."
