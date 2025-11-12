# AWS Infrastructure Automation

Enterprise-grade multi-environment AWS infrastructure deployment using Terraform, Terragrunt, and Jenkins automation workflows.

## Architecture

**3-Tier VPC Design:**
```
Internet Gateway
       ↓
Public Subnet (10.0.1.0/24 | 10.1.1.0/24)
  ├── Bastion Host (secure SSH access)
  └── NAT Gateway
       ↓
Private Subnets (10.0.2.0/24 | 10.1.2.0/24)
  ├── Web Tier (HTTP/HTTPS)
  └── Application Tier (Port 8080)
```

## Features

- **Multi-Environment**: Isolated dev/prod with Terragrunt
- **Remote State**: S3 backend with DynamoDB locking
- **Security-First**: IAM roles, security groups, encrypted storage
- **Cost-Optimized**: S3 lifecycle policies (30d→IA, 90d→Glacier)
- **Automated Deployment**: Jenkins workflow with validation & approval gates

## Quick Start
### Bootstrap State Backend (One-Time)
```bash
cd terraform-state-backend
terraform init
terraform apply
```

### Deploy Infrastructure

**Option 1: Terragrunt (Manual)**
```bash
cd dev  # or prod
terragrunt init
terragrunt plan
terragrunt apply
```

**Option 2: Jenkins Workflow (Recommended)**
- Navigate to Jenkins job
- Select parameters:
  - Environment (dev/prod)
  - AWS Region
  - Optional: Custom VPC name, subnet CIDRs, instance types
- Review plan
- Approve deployment

## Infrastructure Details

### Environments

| Environment | VPC CIDR | Instance Type | S3 Versioning | Encryption |
|-------------|----------|---------------|---------------|------------|
| **Dev** | 10.0.0.0/16 | t3.micro | Disabled | Enabled |
| **Prod** | 10.1.0.0/16 | t3.small | Enabled | Enabled |

### Security Groups

| Tier | Ingress | Source |
|------|---------|--------|
| **Bastion** | SSH (22) | Allowed CIDR only |
| **Web** | HTTP (80), HTTPS (443) | 0.0.0.0/0 |
| | SSH (22) | Bastion SG |
| **App** | Port 8080 | Web SG |
| | SSH (22) | Bastion SG |

### IAM Policies

- **S3 Access**: Scoped to specific bucket only
- **CloudWatch Logs**: Write permissions for instance logs
- **SSM Session Manager**: SSH-less EC2 access

## 🤖 Jenkins Automation Workflow

**Flow:** Validate → Init → Plan → Approval → Apply → Validate → Archive

**Features:**
- Parameter-driven deployment (region, CIDR, instance types)
- Environment-locked CIDR validation
- Manual approval gate before infrastructure changes
- Automatic cleanup on failure
- State file archiving as build artifact

**Validation Stages:**
1. Parameter validation (CIDR ranges, environment)
2. Terraform syntax validation
3. Post-deployment resource verification (EC2 + S3)

## Technologies

- **Terraform**: 1.9.5
- **Terragrunt**: 0.93.4
- **AWS Services**: VPC, EC2, S3, IAM, DynamoDB, CloudWatch
- **CI/CD**: Jenkins (Kubernetes-based agents)

## Prerequisites

- AWS account with appropriate IAM permissions
- Jenkins with:
  - Kubernetes plugin
  - AWS credentials configured
  - Pipeline job created
- Terraform & Terragrunt (auto-installed by pipeline)

## State Management

**Backend Configuration:**
- **Bucket**: `tf-state-bucket9999`
- **Table**: `tf-locks`
- **Encryption**: AES256
- **Versioning**: Enabled
- **Lifecycle**: 30d→IA, 90d→Glacier, 365d→Delete

## Best Practices in use 

- ✅ Infrastructure as Code (100% declarative)
- ✅ GitOps workflow (changes via Git)
- ✅ Immutable infrastructure (replace, not modify)
- ✅ Environment isolation (separate state files)
- ✅ Least-privilege access (scoped IAM policies)
- ✅ Automated validation (pre-deployment checks)
- ✅ Manual approval gates (production safety)
- ✅ State locking (prevents race conditions)
