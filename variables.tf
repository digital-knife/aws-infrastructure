# AWS Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

# Project Configuration
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev, prod, etc.)"
  type        = string
}

variable "owner" {
  description = "Owner/team responsible for resources"
  type        = string
}

# VPC Configuration
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "vpc_name" {
  description = "Custom VPC name (optional)"
  type        = string
  default     = ""
}

variable "vpc_tag" {
  description = "Additional VPC tag (optional)"
  type        = string
  default     = ""
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR (optional, auto-assigned if not provided)"
  type        = string
  default     = ""

  validation {
    condition     = var.public_subnet_cidr == "" || can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "Must be valid CIDR notation or empty string for automatic assignment."
  }
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR (optional, auto-assigned if not provided)"
  type        = string
  default     = ""

  validation {
    condition     = var.private_subnet_cidr == "" || can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "Must be valid CIDR notation or empty string for automatic assignment."
  }
}

# Security Configuration
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH to bastion host"
  type        = string
  default     = "0.0.0.0/0"
}

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Custom S3 bucket name (optional)"
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false
}

variable "enable_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = false
}
