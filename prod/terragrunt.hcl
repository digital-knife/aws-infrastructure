terraform {
  source = "../"
}

include "root" {
  path = find_in_parent_folders("root.hcl")  # Changed from terragrunt.hcl
}

inputs = {
  environment  = "prod"
  project_name = "demo-project"
  owner        = "DevOps-Team"
  
  aws_region = "us-east-1"
  
  vpc_cidr = "10.1.0.0/16"
  vpc_name = "prod-vpc"
  
  public_subnet_cidr  = ""
  private_subnet_cidr = ""
  
  allowed_ssh_cidr = "0.0.0.0/0"
  
  instance_type = "t3.small"
  
  s3_bucket_name    = ""
  enable_versioning = true
  enable_encryption = true
  
  vpc_tag = ""
}