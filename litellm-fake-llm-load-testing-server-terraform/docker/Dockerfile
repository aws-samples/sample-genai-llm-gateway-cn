# Dockerfile

FROM python:3.13-slim

WORKDIR /app

# Install system dependencies if needed
# RUN apt-get update && apt-get install -y ...

COPY requirements.txt /app/requirements.txt

RUN pip install --no-cache-dir -r requirements.txt

COPY . /app

# Create non-root user
RUN useradd --create-home appuser
USER appuser

# Expose the port; ECS will map it
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/')" || exit 1

CMD ["python", "fake_llm_server.py"]
