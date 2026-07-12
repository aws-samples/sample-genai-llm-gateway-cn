###############################################################################
# S3 bucket for config
###############################################################################
#checkov:skip=CKV_AWS_18:Logging bucket circular dependency
#checkov:skip=CKV_AWS_144:Single-region deployment
#checkov:skip=CKV2_AWS_62:Not required for config storage
#checkov:skip=CKV2_AWS_67:Using AWS-managed key rotation
resource "aws_s3_bucket" "config_bucket" {
  bucket_prefix = "litellm-config-"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "alias/aws/s3"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceSSLOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.config_bucket.arn,
          "${aws_s3_bucket.config_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "config_bucket" {
  bucket                  = aws_s3_bucket.config_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Single file upload of `config.yaml`
# In your CDK, you used s3deploy with `include: ['config.yaml']` and `exclude: ['*']` then re-included `config.yaml`.
resource "aws_s3_object" "config_file" {
  bucket = aws_s3_bucket.config_bucket.id
  key    = "config.yaml"
  source = "${path.module}/../../../config/config.yaml" # Adjust path as needed
  etag   = filemd5("${path.module}/../../../config/config.yaml")
}