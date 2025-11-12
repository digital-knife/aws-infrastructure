terraform {
  source = "../"
}

include "root" {
  path = find_in_parent_folders("root.hcl")  # Changed from terragrunt.hcl
}

inputs = {
  environment  = "dev"
  project_name = "demo-project"
  owner        = "DevOps-Team"
  
  aws_region = "us-east-1"
  
  vpc_cidr = "10.0.0.0/16"
  vpc_name = "dev-vpc"
  
  public_subnet_cidr  = ""
  private_subnet_cidr = ""
  
  allowed_ssh_cidr = "0.0.0.0/0"
  
  instance_type = "t3.micro"
  
  s3_bucket_name    = ""
  enable_versioning = false
  enable_encryption = false
  
  vpc_tag = ""
}