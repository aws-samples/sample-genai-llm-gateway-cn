#!/bin/bash
# =============================================================================
# mirror-images-to-ecr.sh
# Pre-mirror required container images to your China region ECR.
#
# Run this from a machine that has access to BOTH the global internet and
# your China region ECR (e.g., a global-region EC2, your laptop with VPN,
# or a CI runner).
#
# Usage:
#   export AWS_REGION=cn-northwest-1
#   export AWS_ACCOUNT_ID=107327642275
#   ./scripts/mirror-images-to-ecr.sh
#
# After mirroring, set these in your .env before running deploy.sh:
#   LITELLM_BASE_IMAGE=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com.cn/litellm-proxy:$LITELLM_VERSION
#   PYTHON_BASE_IMAGE=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com.cn/python:3.11-slim
# =============================================================================
set -euo pipefail

source .env 2>/dev/null || true

: "${AWS_REGION:?Set AWS_REGION (e.g., cn-northwest-1)}"
: "${AWS_ACCOUNT_ID:=$(aws sts get-caller-identity --query Account --output text)}"
: "${LITELLM_VERSION:=main-v1.82.3-stable.patch.2}"

# Detect ECR domain suffix
if [[ "$AWS_REGION" == cn-* ]]; then
  ECR_BASE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com.cn"
else
  ECR_BASE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
fi

echo "=== Mirroring images to $ECR_BASE ==="

# Function to create ECR repo if not exists
ensure_repo() {
  local repo_name=$1
  if ! aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" 2>/dev/null; then
    echo "Creating ECR repo: $repo_name"
    aws ecr create-repository --repository-name "$repo_name" --region "$AWS_REGION" \
      --tags Key=project,Value=llmgateway
  fi
}

# Login to ECR
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_BASE"

# --- Mirror 1: LiteLLM proxy image ---
echo ""
echo "=== [1/2] Mirroring LiteLLM proxy image ==="
SRC_IMAGE="ghcr.io/berriai/litellm:${LITELLM_VERSION}"
DST_IMAGE="$ECR_BASE/litellm-proxy:${LITELLM_VERSION}"

ensure_repo "litellm-proxy"

echo "Pulling $SRC_IMAGE ..."
docker pull "$SRC_IMAGE"
docker tag "$SRC_IMAGE" "$DST_IMAGE"
echo "Pushing $DST_IMAGE ..."
docker push "$DST_IMAGE"
echo "✅ LiteLLM proxy mirrored"

# --- Mirror 2: Python base image ---
echo ""
echo "=== [2/2] Mirroring Python base image ==="
SRC_IMAGE="python:3.11-slim"
DST_IMAGE="$ECR_BASE/python:3.11-slim"

ensure_repo "python"

echo "Pulling $SRC_IMAGE ..."
docker pull "$SRC_IMAGE"
docker tag "$SRC_IMAGE" "$DST_IMAGE"
echo "Pushing $DST_IMAGE ..."
docker push "$DST_IMAGE"
echo "✅ Python base mirrored"

echo ""
echo "=== All images mirrored! ==="
echo ""
echo "Add to your .env:"
echo "  LITELLM_BASE_IMAGE=$ECR_BASE/litellm-proxy:${LITELLM_VERSION}"
echo "  PYTHON_BASE_IMAGE=$ECR_BASE/python:3.11-slim"
echo "  PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple  # optional, for faster pip in China"
