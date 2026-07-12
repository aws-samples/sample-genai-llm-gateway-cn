# China regions cannot pull from Docker Hub directly.
# Set PYTHON_BASE_IMAGE to use a China-accessible mirror or pre-mirrored ECR image.
# Default: python:3.11-slim (works in global regions)
ARG PYTHON_BASE_IMAGE=python:3.11-slim
FROM ${PYTHON_BASE_IMAGE}

WORKDIR /app

COPY requirements.txt .

# Use --index-url for China pip mirror when PIP_INDEX_URL is set
ARG PIP_INDEX_URL=""
RUN if [ -n "$PIP_INDEX_URL" ]; then \
      pip install --no-cache-dir -r requirements.txt -i "$PIP_INDEX_URL"; \
    else \
      pip install --no-cache-dir -r requirements.txt; \
    fi

COPY app.py .

# Create non-root user
RUN useradd --create-home appuser
USER appuser

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:3000/bedrock/health/liveliness')" || exit 1

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "3000"]
