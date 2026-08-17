#!/usr/bin/env bash
# Build and push all four service images to their ECR repos. Run this
# locally (not in the Cowork cloud sandbox) — it needs Docker and your AWS
# CLI credentials for account 264502359266.
#
# Usage: ./scripts/build-and-push.sh [tag]
#   tag defaults to the current git short SHA, falling back to "latest".

set -euo pipefail

PROJECT="aws-ecommerce-platform"
ENVIRONMENT="dev"
REGION="eu-west-2"
ACCOUNT_ID="264502359266"
SERVICES=(product cart user order)

TAG="${1:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Logging in to ECR (${REGISTRY})..."
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"

for svc in "${SERVICES[@]}"; do
  repo="${PROJECT}-${ENVIRONMENT}-${svc}"
  image="${REGISTRY}/${repo}:${TAG}"

  echo ""
  echo "=== ${svc}-service -> ${image} ==="
  docker build -t "${image}" "services/${svc}-service"
  docker push "${image}"
done

echo ""
echo "Done. Pushed tag '${TAG}' for: ${SERVICES[*]}"
echo "Update each service's ECS task definition image reference to this tag, then redeploy (build step 9/10)."
