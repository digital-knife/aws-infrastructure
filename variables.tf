variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be valid CIDR notation."
  }
}

variable "vpc_name" {
  description = "Custom VPC name (optional - defaults to environment-vpc)"
  type        = string
  default     = ""
}

variable "vpc_tag" {
  description = "Additional VPC tag (optional)"
  type        = string
  default     = ""
}

# Public Subnet Variables
variable "public_subnet_cidr_1" {
  description = "Public subnet 1 CIDR (optional, auto-assigned if not provided)"
  type        = string
  default     = ""

  validation {
    condition     = var.public_subnet_cidr_1 == "" || can(cidrhost(var.public_subnet_cidr_1, 0))
    error_message = "Must be valid CIDR notation or empty string for automatic assignment."
  }
}

variable "public_subnet_cidr_2" {
  description = "Public subnet 2 CIDR (optional, auto-assigned if not provided)"
  type        = string
  default     = ""

  validation {
    condition     = var.public_subnet_cidr_2 == "" || can(cidrhost(var.public_subnet_cidr_2, 0))
    error_message = "Must be valid CIDR notation or empty string for automatic assignment."
  }
}

# Private Subnet Variables
variable "private_subnet_cidr_1" {
  description = "Private subnet 1 CIDR (optional, auto-assigned if not provided)"
  type        = string
  default     = ""

  validation {
    condition     = var.private_subnet_cidr_1 == "" || can(cidrhost(var.private_subnet_cidr_1, 0))
    error_message = "Must be valid CIDR notation or empty string for automatic assignment."
  }
}

variable "private_subnet_cidr_2" {
  description = "Private subnet 2 CIDR (optional, auto-assigned if not provided)"
  type        = string
  default     = ""

  validation {
    condition     = var.private_subnet_cidr_2 == "" || can(cidrhost(var.private_subnet_cidr_2, 0))
    error_message = "Must be valid CIDR notation or empty string for automatic assignment."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium"], var.instance_type)
    error_message = "Instance type must be t3.micro, t3.small, or t3.medium."
  }
}

variable "s3_bucket_name" {
  description = "S3 bucket name (optional - auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "aws-infrastructure"
}

variable "owner" {
  description = "Owner for tagging"
  type        = string
  default     = "DevOps"
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false
}

variable "enable_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}
