resource "aws_security_group" "bastion" {
  name        = local.sg_bastion_name
  description = "Security group for bastion host - restricted SSH access"
  vpc_id      = aws_vpc.main.id

  # SSH only from allowed CIDR (company network or VPN)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "SSH from company network/VPN only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.sg_bastion_name
      Tier = "Management"
    }
  )
}

# Web Tier Security Group
resource "aws_security_group" "web" {
  name        = local.sg_web_name
  description = "Security group for web tier - HTTP/HTTPS and SSH from bastion"
  vpc_id      = aws_vpc.main.id

  # HTTP from anywhere (will be restricted to ALB later)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  # HTTPS from anywhere (will be restricted to ALB later)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  # SSH from bastion only
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
    description     = "SSH from bastion host only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.sg_web_name
      Tier = "Web"
    }
  )
}

# Application Tier Security Group
resource "aws_security_group" "app" {
  name        = local.sg_app_name
  description = "Security group for application tier - app port from web tier only"
  vpc_id      = aws_vpc.main.id

  # Application port from web tier only
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
    description     = "App port from web tier only"
  }

  # SSH from bastion only
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
    description     = "SSH from bastion host only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.sg_app_name
      Tier = "Application"
    }
  )
}
