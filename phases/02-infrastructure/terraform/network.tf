# VPC
resource "aws_vpc" "main" {
  cidr_block           = local.network_config.vpc.cidr
  enable_dns_hostnames = local.network_config.vpc.enable_dns_hostnames
  enable_dns_support   = local.network_config.vpc.enable_dns_support

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-vpc"
    }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-igw"
    }
  )
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-nat-eip"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Public Subnet (for bastion)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.network_config.subnets.public.cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = local.network_config.subnets.public.map_public_ip

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-${local.network_config.subnets.public.name}"
      Type = "public"
    }
  )
}

# Private Subnet (for internal nodes)
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.network_config.subnets.private.cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = local.network_config.subnets.private.map_public_ip

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-${local.network_config.subnets.private.name}"
      Type = "private"
    }
  )
}

# NAT Gateway (in public subnet for private subnet internet access)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-nat"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-public-rtb"
    }
  )
}

# Route Table for Private Subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_config.name}-private-rtb"
    }
  )
}

# Associate Public Subnet with Public Route Table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Associate Private Subnet with Private Route Table
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}