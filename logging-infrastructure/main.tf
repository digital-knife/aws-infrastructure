# Permanent Logging Infrastructure
# This is created ONCE and never destroyed

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Store THIS infrastructure's state in the state bucket
  # But keep it in a separate key path
  backend "s3" {
    bucket         = "tf-state-bucket9999"
    key            = "permanent/logging-infrastructure.tfstate" # Separate path
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "tf-locks"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

data "aws_caller_identity" "current" {}

# ============================================================================
# SEPARATE S3 BUCKET - ONLY FOR ALB LOGS
# ============================================================================

resource "aws_s3_bucket" "centralized_alb_logs" {
  bucket = "centralized-alb-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name      = "Centralized ALB Logs"
    Purpose   = "ALB Access Logs - All Environments"
    ManagedBy = "Terraform"
    Permanent = "true"
  }
}

# Block public access to log bucket
resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.centralized_alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy - delete logs after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.centralized_alb_logs.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Bucket policy - allow ALB to write logs
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.centralized_alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ALBAccessLogWrite"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::127311923021:root" # ELB service account for us-east-1
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.centralized_alb_logs.arn}/*"
      }
    ]
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUPS - FOR APPLICATION AND USER DATA LOGS
# ============================================================================

resource "aws_cloudwatch_log_group" "centralized_user_data_logs" {
  name              = "/aws/ec2/user-data/centralized"
  retention_in_days = 14

  tags = {
    Name      = "Centralized User Data Logs"
    ManagedBy = "Terraform"
    Permanent = "true"
  }
}

resource "aws_cloudwatch_log_group" "centralized_app_logs" {
  name              = "/aws/applications/centralized"
  retention_in_days = 30

  tags = {
    Name      = "Centralized Application Logs"
    ManagedBy = "Terraform"
    Permanent = "true"
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "alb_logs_bucket" {
  description = "S3 bucket name for ALB logs (reference this in main infrastructure)"
  value       = aws_s3_bucket.centralized_alb_logs.id
}

output "alb_logs_bucket_arn" {
  description = "ARN of ALB logs bucket"
  value       = aws_s3_bucket.centralized_alb_logs.arn
}

output "user_data_log_group" {
  description = "CloudWatch log group for user data logs"
  value       = aws_cloudwatch_log_group.centralized_user_data_logs.name
}

output "app_log_group" {
  description = "CloudWatch log group for application logs"
  value       = aws_cloudwatch_log_group.centralized_app_logs.name
}

output "summary" {
  description = "Summary of permanent logging infrastructure"
  value = {
    alb_logs_bucket     = aws_s3_bucket.centralized_alb_logs.id
    alb_logs_s3_path    = "s3://${aws_s3_bucket.centralized_alb_logs.id}/"
    user_data_logs      = aws_cloudwatch_log_group.centralized_user_data_logs.name
    app_logs            = aws_cloudwatch_log_group.centralized_app_logs.name
    log_retention_days  = "ALB: 90 days, User Data: 14 days, App: 30 days"
    where_to_check_logs = "AWS Console → S3 → ${aws_s3_bucket.centralized_alb_logs.id}"
  }
}
