###############################################################################
# Layer 1 – VPC, Subnets, NAT Gateways, Route Tables
# coder4gov.com — Gov Demo Environment
#
# Creates:
#   - VPC with DNS support/hostnames (INFRA-007, INFRA-008)
#   - 2 public subnets  (ALB, NAT Gateway)
#   - 4 private subnets (2 system + 2 workloads, one per AZ)
#   - Internet Gateway
#   - NAT Gateway per AZ for HA
#   - Route tables (public → IGW, private → NAT GW)
#   - VPC Flow Logs → CloudWatch (SEC-011)
#
# Subnet layout (10.0.0.0/16):
#   Public:           10.0.0.0/20, 10.0.16.0/20       (/20 = 4,094 hosts each)
#   Private-system:   10.0.32.0/20, 10.0.48.0/20
#   Private-workload: 10.0.64.0/20, 10.0.80.0/20
###############################################################################

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Subnet CIDR allocation — /20 blocks within the /16 VPC
  public_subnets           = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_system_subnets   = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + var.az_count)]
  private_workload_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + (var.az_count * 2))]

  all_tags = merge(var.tags, {
    Project = var.project_name
  })
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-vpc"
  })
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-igw"
  })
}

# ---------------------------------------------------------------------------
# Public Subnets (ALB / NAT Gateway)
# ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.all_tags, {
    Name                                       = "${var.project_name}-public-${local.azs[count.index]}"
    Tier                                       = "public"
    "kubernetes.io/role/elb"                   = "1"
    "karpenter.sh/discovery"                   = var.project_name
    "kubernetes.io/cluster/${var.project_name}" = "shared"
  })
}

# ---------------------------------------------------------------------------
# Private Subnets — System (EKS system node group, platform workloads)
# ---------------------------------------------------------------------------

resource "aws_subnet" "private_system" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_system_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.all_tags, {
    Name                                       = "${var.project_name}-private-system-${local.azs[count.index]}"
    Tier                                       = "private"
    SubnetType                                 = "system"
    "kubernetes.io/role/internal-elb"          = "1"
    "karpenter.sh/discovery"                   = var.project_name
    "kubernetes.io/cluster/${var.project_name}" = "shared"
  })
}

# ---------------------------------------------------------------------------
# Private Subnets — Workloads (Karpenter workspace nodes)
# ---------------------------------------------------------------------------

resource "aws_subnet" "private_workload" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_workload_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.all_tags, {
    Name                                       = "${var.project_name}-private-workload-${local.azs[count.index]}"
    Tier                                       = "private"
    SubnetType                                 = "workload"
    "kubernetes.io/role/internal-elb"          = "1"
    "karpenter.sh/discovery"                   = var.project_name
    "kubernetes.io/cluster/${var.project_name}" = "shared"
  })
}

# ---------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
# ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count  = var.az_count
  domain = "vpc"

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-nat-eip-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

# ---------------------------------------------------------------------------
# NAT Gateways — one per AZ for HA (INFRA-007, Decision #6)
# ---------------------------------------------------------------------------

resource "aws_nat_gateway" "main" {
  count = var.az_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-nat-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

# ---------------------------------------------------------------------------
# Route Tables — Public
# ---------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Route Tables — Private (one per AZ, routes to per-AZ NAT GW)
# ---------------------------------------------------------------------------

resource "aws_route_table" "private" {
  count = var.az_count

  vpc_id = aws_vpc.main.id

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-private-rt-${local.azs[count.index]}"
  })
}

resource "aws_route" "private_nat" {
  count = var.az_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

# Associate system subnets with their AZ's private route table
resource "aws_route_table_association" "private_system" {
  count = var.az_count

  subnet_id      = aws_subnet.private_system[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Associate workload subnets with their AZ's private route table
resource "aws_route_table_association" "private_workload" {
  count = var.az_count

  subnet_id      = aws_subnet.private_workload[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ---------------------------------------------------------------------------
# VPC Flow Logs → CloudWatch Logs (SEC-011, LOG-002)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.project_name}"
  retention_in_days = 365

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-vpc-flow-logs"
  })
}

data "aws_iam_policy_document" "flow_log_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "flow_log_publish" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"]
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name               = "${var.project_name}-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume.json

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-vpc-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name   = "${var.project_name}-vpc-flow-logs-publish"
  role   = aws_iam_role.vpc_flow_logs.id
  policy = data.aws_iam_policy_document.flow_log_publish.json
}

resource "aws_flow_log" "main" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-vpc-flow-log"
  })
}
