resource "aws_s3_bucket" "access_log_bucket" {
  #checkov:skip=CKV_AWS_18:Logging bucket cannot log to itself
  #checkov:skip=CKV_AWS_144:Single-region deployment
  #checkov:skip=CKV_AWS_145:ALB access logs require AES256 encryption, KMS not supported
  #checkov:skip=CKV2_AWS_62:Not required for access log storage
  #checkov:skip=CKV2_AWS_67:Using AWS-managed key rotation
  bucket_prefix = "access-logs-"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "access_log_bucket" {
  bucket = aws_s3_bucket.access_log_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_log_bucket" {
  #checkov:skip=CKV2_AWS_67:Using AWS-managed key rotation for AES256
  bucket = aws_s3_bucket.access_log_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "access_log_bucket" {
  bucket = aws_s3_bucket.access_log_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceSSLOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.access_log_bucket.arn,
          "${aws_s3_bucket.access_log_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowELBLogDelivery"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_log_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "access_log_bucket" {
  bucket                  = aws_s3_bucket.access_log_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "access_log_bucket" {
  #checkov:skip=CKV_AWS_300:Lifecycle rule configured with appropriate retention
  bucket = aws_s3_bucket.access_log_bucket.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }
}