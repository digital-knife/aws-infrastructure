# Provider configuration
provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC - Main network container
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    local.common_tags,
    {
      Name = local.vpc_name
    }
  )
}

# Internet Gateway - Provides internet access for public subnet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = local.igw_name
    }
  )
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-eip"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway for private subnet internet access
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = merge(
    local.common_tags,
    {
      Name = local.nat_name
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Public Subnet - Resources here get public IPs and internet access
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr != "" ? var.public_subnet_cidr : cidrsubnet(var.vpc_cidr, 8, 1)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = merge(
    local.common_tags,
    {
      Name = local.public_subnet_name
      Type = "Public"
    }
  )
}

# Private Subnet - Resources here are isolated from direct internet access
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr != "" ? var.private_subnet_cidr : cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(
    local.common_tags,
    {
      Name = local.private_subnet_name
      Type = "Private"
    }
  )
}

# Public Route Table - Routes traffic to internet gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.public_rt_name
    }
  )
}

# Private Route Table - Routes traffic to NAT gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.private_rt_name
    }
  )
}

# Associate public route table with public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Associate private route table with private subnet
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
