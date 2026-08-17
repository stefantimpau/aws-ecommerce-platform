#!/usr/bin/env bash
# Build the React frontend against the live Terraform outputs, sync it to
# the frontend S3 bucket, and invalidate the CloudFront cache so the new
# build is actually served (CloudFront caches index.html for up to an
# hour otherwise — see terraform/modules/static-frontend default_ttl).
#
# Run this locally (not the Cowork cloud sandbox) — it needs Node, your
# AWS CLI credentials for account 264502359266, and a `terraform apply`
# that's already succeeded (this script reads its outputs).
#
# Usage: ./scripts/deploy-frontend.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/environments/dev"
FRONTEND_DIR="${ROOT_DIR}/frontend"

echo "Reading Terraform outputs from ${TF_DIR}..."
API_URL=$(terraform -chdir="${TF_DIR}" output -raw api_url)
FRONTEND_URL=$(terraform -chdir="${TF_DIR}" output -raw frontend_url)
COGNITO_DOMAIN=$(terraform -chdir="${TF_DIR}" output -raw cognito_hosted_ui_domain)
COGNITO_CLIENT_ID=$(terraform -chdir="${TF_DIR}" output -raw cognito_user_pool_client_id)
CLOUDFRONT_DOMAIN=$(terraform -chdir="${TF_DIR}" output -raw cloudfront_domain_name)
FRONTEND_BUCKET=$(terraform -chdir="${TF_DIR}" output -raw frontend_bucket_name)
DISTRIBUTION_ID=$(terraform -chdir="${TF_DIR}" output -raw cloudfront_distribution_id)

# Both URLs from `terraform output` can have a trailing slash — strip it
# so api.js's `${API_BASE_URL}${path}` doesn't end up with a double slash.
API_URL="${API_URL%/}"
FRONTEND_URL="${FRONTEND_URL%/}"

echo "  API URL (custom domain, step 19):       ${API_URL}"
echo "  Frontend URL (custom domain, step 19):  ${FRONTEND_URL}"
echo "  Cognito domain:                          ${COGNITO_DOMAIN}"
echo "  CloudFront default domain:               ${CLOUDFRONT_DOMAIN}"
echo "  Frontend bucket:                         ${FRONTEND_BUCKET}"
echo "  Distribution ID:                         ${DISTRIBUTION_ID}"

cat > "${FRONTEND_DIR}/.env.production" <<EOF
VITE_API_BASE_URL=${API_URL}
VITE_COGNITO_DOMAIN=${COGNITO_DOMAIN}
VITE_COGNITO_CLIENT_ID=${COGNITO_CLIENT_ID}
VITE_COGNITO_REDIRECT_URI=${FRONTEND_URL}
VITE_CLOUDFRONT_DOMAIN=${CLOUDFRONT_DOMAIN}
EOF

echo ""
echo "Building..."
(cd "${FRONTEND_DIR}" && npm install && npm run build)

echo ""
echo "Syncing dist/ -> s3://${FRONTEND_BUCKET}..."
aws s3 sync "${FRONTEND_DIR}/dist" "s3://${FRONTEND_BUCKET}" --delete

echo ""
echo "Invalidating CloudFront cache..."
aws cloudfront create-invalidation --distribution-id "${DISTRIBUTION_ID}" --paths "/*" --query 'Invalidation.Id' --output text

echo ""
echo "Done. ${FRONTEND_URL} (or the default domain: https://${CLOUDFRONT_DOMAIN})"
