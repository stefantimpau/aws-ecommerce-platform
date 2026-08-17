locals {
  name = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = local.name
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-igw"
  })
}

# ---------------------------------------------------------------------------
# Subnets — 2 public, 2 private-app, 2 private-data (one per AZ)
# ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-${var.azs[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private_app" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-app-${var.azs[count.index]}"
    Tier = "private-app"
  })
}

resource "aws_subnet" "private_data" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_data_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-data-${var.azs[count.index]}"
    Tier = "private-data"
  })
}

# ---------------------------------------------------------------------------
# NAT Gateway(s) — single NAT (AZ 0) by default to control cost; set
# single_nat_gateway = false for one-per-AZ resilience. See docs/adr.
# ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.azs)
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name}-nat-eip-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = var.single_nat_gateway ? 1 : length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.name}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Route tables
# ---------------------------------------------------------------------------

# Single public route table, shared by both public subnets.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table(s) — one per AZ so each can point at its own NAT GW
# when single_nat_gateway = false; both point at the same NAT when true.
resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-rt-${var.azs[count.index]}"
  })
}

# Private-app subnets need outbound internet (via NAT) for ECR pulls, SSM, etc.
resource "aws_route_table_association" "private_app" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Private-data subnets also route through NAT (e.g. for SSM/CloudWatch agent
# traffic from RDS-adjacent tooling); RDS itself makes no outbound calls.
resource "aws_route_table_association" "private_data" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
