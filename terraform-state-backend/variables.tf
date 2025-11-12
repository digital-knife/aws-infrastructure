variable "aws_region" {
  description = "AWS region for state backend"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name of S3 bucket for Terraform state"
  type        = string
  default     = "tf-state-bucket9999"
}

variable "dynamodb_table_name" {
  description = "Name of DynamoDB table for state locking"
  type        = string
  default     = "tf-locks"
}
