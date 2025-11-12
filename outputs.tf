# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

# Subnet Outputs
output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = aws_subnet.private.id
}

output "public_subnet_cidr" {
  description = "Public subnet CIDR block"
  value       = aws_subnet.public.cidr_block
}

output "private_subnet_cidr" {
  description = "Private subnet CIDR block"
  value       = aws_subnet.private.cidr_block
}

# EC2 Instance Outputs
output "public_ec2_id" {
  description = "Public EC2 instance ID"
  value       = aws_instance.public.id
}

output "public_ec2_ip" {
  description = "Public EC2 instance public IP"
  value       = aws_instance.public.public_ip
}

output "private_ec2_id" {
  description = "Private EC2 instance ID"
  value       = aws_instance.private.id
}

output "private_ec2_ip" {
  description = "Private EC2 instance private IP"
  value       = aws_instance.private.private_ip
}

# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.demo_bucket.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.demo_bucket.arn
}

# Security Group Outputs
output "bastion_security_group_id" {
  description = "Bastion security group ID"
  value       = aws_security_group.bastion.id
}

output "web_security_group_id" {
  description = "Web tier security group ID"
  value       = aws_security_group.web.id
}

output "app_security_group_id" {
  description = "Application tier security group ID"
  value       = aws_security_group.app.id
}

# IAM Outputs
output "ec2_iam_role_arn" {
  description = "EC2 IAM role ARN"
  value       = aws_iam_role.ec2_role.arn
}

output "ec2_instance_profile_name" {
  description = "EC2 instance profile name"
  value       = aws_iam_instance_profile.ec2_profile.name
}

# Network Gateway Outputs
output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway Elastic IP"
  value       = aws_eip.nat.public_ip
}

# Environment Info
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "encryption_type" {
  description = "S3 encryption type"
  value       = var.enable_encryption ? "AES256 (S3-managed)" : "None"
}
