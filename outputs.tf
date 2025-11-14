# ============================================================================
# VPC OUTPUTS
# ============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "vpc_name" {
  description = "VPC Name"
  value       = local.vpc_name
}

# ============================================================================
# SUBNET OUTPUTS
# ============================================================================

output "public_subnet_1_id" {
  description = "Public subnet 1 ID"
  value       = aws_subnet.public_1.id
}

output "public_subnet_2_id" {
  description = "Public subnet 2 ID"
  value       = aws_subnet.public_2.id
}

output "private_subnet_1_id" {
  description = "Private subnet 1 ID"
  value       = aws_subnet.private_1.id
}

output "private_subnet_2_id" {
  description = "Private subnet 2 ID"
  value       = aws_subnet.private_2.id
}

# ============================================================================
# APPLICATION LOAD BALANCER OUTPUTS
# ============================================================================

output "alb_dns_name" {
  description = "ALB DNS name - Use this to access your application"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_zone_id" {
  description = "ALB Zone ID (for Route53 alias records)"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = aws_lb_target_group.web.arn
}

# ============================================================================
# EC2 INSTANCE OUTPUTS
# ============================================================================

output "bastion_instance_id" {
  description = "Bastion instance ID"
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Bastion public IP"
  value       = aws_instance.bastion.public_ip
}

output "bastion_availability_zone" {
  description = "Bastion availability zone"
  value       = aws_instance.bastion.availability_zone
}

output "web_1_instance_id" {
  description = "Web server 1 instance ID"
  value       = aws_instance.web_1.id
}

output "web_1_private_ip" {
  description = "Web server 1 private IP"
  value       = aws_instance.web_1.private_ip
}

output "web_1_availability_zone" {
  description = "Web server 1 availability zone"
  value       = aws_instance.web_1.availability_zone
}

output "web_2_instance_id" {
  description = "Web server 2 instance ID"
  value       = aws_instance.web_2.id
}

output "web_2_private_ip" {
  description = "Web server 2 private IP"
  value       = aws_instance.web_2.private_ip
}

output "web_2_availability_zone" {
  description = "Web server 2 availability zone"
  value       = aws_instance.web_2.availability_zone
}

# ============================================================================
# NETWORK OUTPUTS
# ============================================================================

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway public IP"
  value       = aws_eip.nat.public_ip
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

# ============================================================================
# S3 OUTPUTS
# ============================================================================

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.demo_bucket.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.demo_bucket.arn
}

# ============================================================================
# SECURITY GROUP OUTPUTS
# ============================================================================

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "bastion_security_group_id" {
  description = "Bastion security group ID"
  value       = aws_security_group.bastion.id
}

output "web_security_group_id" {
  description = "Web server security group ID"
  value       = aws_security_group.web.id
}

# ============================================================================
# ACCESS INFORMATION
# ============================================================================

output "application_url" {
  description = "Access your application here"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ssm_bastion_command" {
  description = "Command to access bastion via SSM Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${var.aws_region}"
}

output "ssm_web_1_command" {
  description = "Command to access web server 1 via SSM Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.web_1.id} --region ${var.aws_region}"
}

output "ssm_web_2_command" {
  description = "Command to access web server 2 via SSM Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.web_2.id} --region ${var.aws_region}"
}

# ============================================================================
# SUMMARY OUTPUT (Pretty formatted for cloud-receipt.json)
# ============================================================================

output "deployment_summary" {
  description = "Deployment summary"
  value = {
    environment = var.environment
    region      = var.aws_region
    vpc = {
      id   = aws_vpc.main.id
      cidr = aws_vpc.main.cidr_block
      name = local.vpc_name
    }
    load_balancer = {
      dns_name = aws_lb.main.dns_name
      url      = "http://${aws_lb.main.dns_name}"
    }
    instances = {
      bastion = {
        id        = aws_instance.bastion.id
        public_ip = aws_instance.bastion.public_ip
        az        = aws_instance.bastion.availability_zone
      }
      web_1 = {
        id         = aws_instance.web_1.id
        private_ip = aws_instance.web_1.private_ip
        az         = aws_instance.web_1.availability_zone
      }
      web_2 = {
        id         = aws_instance.web_2.id
        private_ip = aws_instance.web_2.private_ip
        az         = aws_instance.web_2.availability_zone
      }
    }
    high_availability = {
      availability_zones = [
        aws_instance.web_1.availability_zone,
        aws_instance.web_2.availability_zone
      ]
      health_check_path     = "/"
      health_check_interval = "30s"
    }
  }
}
