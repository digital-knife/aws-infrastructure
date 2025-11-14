# Get AWS account ID for tagging and resource naming
data "aws_caller_identity" "current" {}

locals {
  # Base naming prefix
  name_prefix = "${var.project_name}-${var.environment}"

  # Common tags applied to all resources - with optional vpc_tag
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      AccountID   = data.aws_caller_identity.current.account_id
    },
    var.vpc_tag != "" ? { CustomTag = var.vpc_tag } : {}
  )

  # VPC and Networking Names - support custom vpc_name from pipeline
  vpc_name = var.vpc_name != "" ? var.vpc_name : "${local.name_prefix}-vpc"
  igw_name = "${local.name_prefix}-igw"
  nat_name = "${local.name_prefix}-nat"

  # Security Group Names
  sg_alb_name     = "${local.name_prefix}-sg-alb"
  sg_bastion_name = "${local.name_prefix}-sg-bastion"
  sg_web_name     = "${local.name_prefix}-sg-web"

  # IAM Role Names
  iam_role_ec2_name    = "${local.name_prefix}-ec2-role"
  iam_profile_ec2_name = "${local.name_prefix}-ec2-profile"

  # S3 Bucket Name (must be globally unique)
  s3_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${local.name_prefix}-bucket-${data.aws_caller_identity.current.account_id}"
}
