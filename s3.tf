# S3 Bucket for demo purposes
resource "aws_s3_bucket" "demo_bucket" {
  bucket = local.s3_bucket_name

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
