# AWS Infrastructure

Terraform-managed AWS infrastructure with VPC, EC2 instances, and CloudWatch monitoring.

## Features

- Multi-AZ VPC with public/private subnets
- EC2 web servers with auto-scaling ready
- Security groups with least-privilege access
- CloudWatch monitoring and alarms
- S3 backend for state management
- Modular and reusable design

## Quick Start
```bash
git clone https://github.com/digital-knife/aws-infrastructure.git
cd aws-infrastructure/terraform

# Configure AWS credentials
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_DEFAULT_REGION=us-east-1

# Deploy infrastructure
terraform init
terraform plan
terraform apply

# Get outputs
terraform output
```

## Project Structure
```
terraform/
├── main.tf                     # Root module
├── variables.tf                # Input variables
├── outputs.tf                  # Resource outputs
├── backend.tf                  # S3 state backend
├── modules/
│   ├── vpc/                    # Network infrastructure
│   ├── ec2/                    # Compute instances
│   ├── security/               # Security groups
│   └── monitoring/             # CloudWatch resources
└── environments/
    ├── dev/                    # Development config
    └── prod/                   # Production config
```

## Resources Created

**Networking:** VPC, public/private subnets, Internet Gateway, NAT Gateway, route tables

**Compute:** EC2 instances, SSH key pairs, elastic IPs

**Security:** Security groups (SSH, HTTP, HTTPS), IAM roles

**Monitoring:** CloudWatch alarms, SNS topics, metric dashboards

## Configuration

Edit `terraform/variables.tf` to customize:

**Region:** AWS region and availability zones

**Instance:** AMI, instance type, key pair name

**Network:** CIDR blocks, subnet configuration

**Monitoring:** Alarm thresholds, notification emails

## Outputs
```bash
# View all outputs
terraform output

# Specific values
terraform output vpc_id
terraform output web_server_public_ip
```

## Destroy Infrastructure
```bash
terraform destroy
```

**Warning:** This deletes all resources. State file is preserved in S3.

## Cost Optimization

Default configuration uses:
- t2.micro instances (free tier eligible)
- Single NAT Gateway
- Minimal CloudWatch metrics

Scale up in `variables.tf` for production workloads.
