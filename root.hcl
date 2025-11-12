remote_state {
  backend = "s3"
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  
  config = {
    bucket         = "tf-state-bucket9999"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-locks"
    encrypt        = true
    
    # No KMS key needed - uses S3-managed encryption
    skip_credentials_validation = false
    skip_metadata_api_check     = false
    skip_region_validation      = false
  }
}

# Shared inputs across all environments
inputs = {
  aws_region   = "us-east-1"
  project_name = "demo-project"
  owner        = "DevOps-Team"
}