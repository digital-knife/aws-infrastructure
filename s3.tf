# S3 Bucket for demo purposes
resource "aws_s3_bucket" "demo_bucket" {
  bucket        = local.s3_bucket_name
  force_destroy = true

  tags = merge(
    local.common_tags,
    {
      Name = local.s3_bucket_name
    }
  )
}

# Enable versioning if specified
resource "aws_s3_bucket_versioning" "demo_bucket" {
  bucket = aws_s3_bucket.demo_bucket.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Server-side encryption with AES256 (S3-managed keys)
resource "aws_s3_bucket_server_side_encryption_configuration" "demo_bucket" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.demo_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # S3-managed encryption, no KMS needed
    }
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "demo_bucket" {
  bucket = aws_s3_bucket.demo_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule to transition old objects to cheaper storage
resource "aws_s3_bucket_lifecycle_configuration" "demo_bucket" {
  bucket = aws_s3_bucket.demo_bucket.id

  rule {
    id     = "transition-old-objects"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# Data source to get the ELB service account for the current region
# This is needed for the bucket policy to allow ALB to write logs
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "centralized-alb-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true

  tags = merge(
    local.common_tags,
    {
      Name        = "ALB Access Logs - ${data.aws_region.current.name}"
      Purpose     = "ALB Access Logs"
      Environment = var.environment
    }
  )
}

# BEST PRACTICE: Enable versioning for compliance and audit trail
resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# BEST PRACTICE: Encrypt ALB logs at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# BEST PRACTICE: Block all public access to logs
resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# BEST PRACTICE: Lifecycle policy to manage log retention and costs
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "alb-log-retention"
    status = "Enabled"

    # Keep logs in Standard for 30 days (for quick access/analysis)
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Move to Glacier after 90 days (for compliance/long-term retention)
    transition {
      days          = 90
      storage_class = "GLACIER_IR" # Instant Retrieval - better for occasional access
    }

    # Delete logs after 1 year (adjust based on compliance requirements)
    expiration {
      days = 365
    }

    # Clean up incomplete multipart uploads to avoid costs
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# CRITICAL: S3 bucket policy to allow ALB to write access logs
# Without this policy, ALB cannot write logs and will fail
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "elasticloadbalancing.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = [
          "${aws_s3_bucket.alb_logs.arn}/*"
        ]
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.alb_logs.arn
      },
      # Legacy support for older ALB service account (region-specific)
      {
        Sid    = "AWSELBServiceAccountWrite"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_elb_service_account.main.id}:root"
        }
        Action = "s3:PutObject"
        Resource = [
          "${aws_s3_bucket.alb_logs.arn}/*"
        ]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}
