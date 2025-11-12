locals {
  # Common naming prefix
  name_prefix = "${var.project_name}-${var.environment}"

  # Common tags applied to all resources - with optional vpc_tag
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    },
    var.vpc_tag != "" ? { CustomTag = var.vpc_tag } : {}
  )

  # VPC and Networking Names - support custom vpc_name from pipeline
  vpc_name            = var.vpc_name != "" ? var.vpc_name : "${local.name_prefix}-vpc"
  igw_name            = "${local.name_prefix}-igw"
  nat_name            = "${local.name_prefix}-nat"
  public_subnet_name  = "${local.name_prefix}-public-subnet"
  private_subnet_name = "${local.name_prefix}-private-subnet"
  public_rt_name      = "${local.name_prefix}-public-rt"
  private_rt_name     = "${local.name_prefix}-private-rt"

  # Security Group Names
  sg_bastion_name = "${local.name_prefix}-sg-bastion"
  sg_web_name     = "${local.name_prefix}-sg-web"
  sg_app_name     = "${local.name_prefix}-sg-app"

  # IAM Role Names
  iam_role_ec2_name    = "${local.name_prefix}-ec2-role"
  iam_profile_ec2_name = "${local.name_prefix}-ec2-profile"

  # S3 Bucket Names - support custom s3_bucket_name from pipeline
  s3_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${local.name_prefix}-demo-bucket-${data.aws_caller_identity.current.account_id}"

  # KMS Key Aliases
  kms_s3_alias = "alias/${local.name_prefix}-s3-key"

  # CloudWatch Log Group Names
  log_group_vpc = "/aws/vpc/${local.name_prefix}"
  log_group_ec2 = "/aws/ec2/${local.name_prefix}"
  log_group_s3  = "/aws/s3/${local.name_prefix}"
}
