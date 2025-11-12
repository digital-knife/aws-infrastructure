resource "aws_iam_role" "ec2_role" {
  name = local.iam_role_ec2_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

# Specific S3 policy - ONLY for our bucket (NO KMS)
resource "aws_iam_policy" "ec2_s3_access" {
  name        = "${local.iam_role_ec2_name}-s3-policy"
  description = "Allow EC2 to access ONLY specific S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListSpecificBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.demo_bucket.arn
      },
      {
        Sid    = "ReadWriteSpecificBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.demo_bucket.arn}/*"
      }
    ]
  })

  tags = local.common_tags
}

# CloudWatch Logs policy
resource "aws_iam_policy" "ec2_cloudwatch_logs" {
  name        = "${local.iam_role_ec2_name}-cloudwatch-policy"
  description = "Allow EC2 to write to CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudWatchLogsAccess"
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/${local.name_prefix}*"
    }]
  })

  tags = local.common_tags
}

# SSM policy for Session Manager (replaces SSH keys)
resource "aws_iam_policy" "ec2_ssm_access" {
  name        = "${local.iam_role_ec2_name}-ssm-policy"
  description = "Allow EC2 to use SSM Session Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SSMSessionManager"
      Effect = "Allow"
      Action = [
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })

  tags = local.common_tags
}

# Attach policies to role
resource "aws_iam_role_policy_attachment" "ec2_s3" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_access.arn
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_cloudwatch_logs.arn
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_ssm_access.arn
}

# Instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = local.iam_profile_ec2_name
  role = aws_iam_role.ec2_role.name

  tags = local.common_tags
}
