# Data source for available AZs
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

# Internet Gateway - Provides internet access for public subnets
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

# NAT Gateway for private subnet internet access (placed in public subnet 1)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  tags = merge(
    local.common_tags,
    {
      Name = local.nat_name
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# ============================================================================
# PUBLIC SUBNETS (2 AZs for ALB requirement)
# ============================================================================

# Public Subnet 1 - AZ1
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_1 != "" ? var.public_subnet_cidr_1 : cidrsubnet(var.vpc_cidr, 8, 1)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public-subnet-1"
      Type = "Public"
      AZ   = data.aws_availability_zones.available.names[0]
    }
  )
}

# Public Subnet 2 - AZ2
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_2 != "" ? var.public_subnet_cidr_2 : cidrsubnet(var.vpc_cidr, 8, 11)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[1]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public-subnet-2"
      Type = "Public"
      AZ   = data.aws_availability_zones.available.names[1]
    }
  )
}

# ============================================================================
# PRIVATE SUBNETS (2 AZs for HA web servers)
# ============================================================================

# Private Subnet 1 - AZ1
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_1 != "" ? var.private_subnet_cidr_1 : cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-subnet-1"
      Type = "Private"
      AZ   = data.aws_availability_zones.available.names[0]
    }
  )
}

# Private Subnet 2 - AZ2
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_2 != "" ? var.private_subnet_cidr_2 : cidrsubnet(var.vpc_cidr, 8, 12)
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-subnet-2"
      Type = "Private"
      AZ   = data.aws_availability_zones.available.names[1]
    }
  )
}

# ============================================================================
# ROUTE TABLES
# ============================================================================

# Public Route Table - Routes traffic to Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public-rt"
      Type = "Public"
    }
  )
}

# Private Route Table - Routes traffic to NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-rt"
      Type = "Private"
    }
  )
}

# ============================================================================
# ROUTE TABLE ASSOCIATIONS
# ============================================================================

# Associate public route table with public subnet 1
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# Associate public route table with public subnet 2
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Associate private route table with private subnet 1
resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

# Associate private route table with private subnet 2
resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}
