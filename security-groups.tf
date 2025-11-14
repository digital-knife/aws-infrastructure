# ============================================================================
# ALB Security Group - Allows HTTP/HTTPS from internet
# ============================================================================

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "Security group for Application Load Balancer - HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  # HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  # HTTPS from anywhere (for future SSL/TLS)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  # Outbound to web servers
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
      Name = "${local.name_prefix}-sg-alb"
      Tier = "LoadBalancer"
    }
  )
}

# ============================================================================
# Bastion Security Group - SSH access for administration
# ============================================================================

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-sg-bastion"
  description = "Security group for bastion host - SSH access for administration"
  vpc_id      = aws_vpc.main.id

  # SSH from allowed CIDR (customize this!)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # TODO: Restrict to your IP in production
    description = "SSH from allowed IPs"
  }

  # Allow all outbound (for SSM, yum updates, etc.)
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
      Name = "${local.name_prefix}-sg-bastion"
      Tier = "Management"
    }
  )
}

# ============================================================================
# Web Server Security Group - HTTP from ALB only, SSH from bastion
# ============================================================================

resource "aws_security_group" "web" {
  name        = "${local.name_prefix}-sg-web"
  description = "Security group for web servers - HTTP from ALB, SSH from bastion"
  vpc_id      = aws_vpc.main.id

  # HTTP from ALB only
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTP from ALB only"
  }

  # SSH from bastion only
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
    description     = "SSH from bastion only"
  }

  # Allow all outbound (for yum updates, external API calls if needed)
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
      Name = "${local.name_prefix}-sg-web"
      Tier = "Web"
    }
  )
}
