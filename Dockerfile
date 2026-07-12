# checkov:skip=CKV_DOCKER_7:Base image version pinned via LITELLM_VERSION ARG
ARG LITELLM_VERSION=main-v1.82.3-stable.patch.2
# China regions cannot pull from ghcr.io directly.
# Set LITELLM_BASE_IMAGE to use a pre-mirrored image in ECR or a China-accessible registry.
# Default: ghcr.io (works in global regions)
ARG LITELLM_BASE_IMAGE=ghcr.io/berriai/litellm:${LITELLM_VERSION}
FROM ${LITELLM_BASE_IMAGE}

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness')"]

# Run as non-root user
USER nobody
