# Shared Infrastructure Module
# Creates VPC, subnets, S3 buckets, and IAM roles for k0rdent training labs

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  common_tags = {
    Project     = "k0rdent-training"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}

#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

#------------------------------------------------------------------------------
# Public Subnets (for NAT Gateways and Bastion)
#------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-${local.azs[count.index]}"
    Type = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#------------------------------------------------------------------------------
# Private Subnets (for Lab Instances)
#------------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 6, count.index + 2) # /22 subnets
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-${local.azs[count.index]}"
    Type = "private"
  })
}

#------------------------------------------------------------------------------
# GPU Subnet (specific AZ with P3/P4 capacity)
#------------------------------------------------------------------------------
resource "aws_subnet" "gpu" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 100)
  availability_zone = var.gpu_az

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-gpu-${var.gpu_az}"
    Type = "gpu"
  })
}

#------------------------------------------------------------------------------
# NAT Gateway (single for cost savings in lab environment)
#------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-eip"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "gpu" {
  subnet_id      = aws_subnet.gpu.id
  route_table_id = aws_route_table.private.id
}

#------------------------------------------------------------------------------
# S3 Buckets
#------------------------------------------------------------------------------
# NOTE: tfstate bucket is created by lab-provision.sh script before terraform runs
# We reference it as a data source to avoid conflicts
data "aws_s3_bucket" "tfstate" {
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "images" {
  bucket = "${var.project_name}-images-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-images"
  })
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-artifacts"
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

#------------------------------------------------------------------------------
# Security Groups
#------------------------------------------------------------------------------

# Bastion Security Group
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from allowed IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-bastion-sg"
  })
}

# Lab Instance Security Group
resource "aws_security_group" "lab_instance" {
  name        = "${var.project_name}-lab-instance-sg"
  description = "Security group for lab instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "All traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-lab-instance-sg"
  })
}

# K8s Cluster Security Group
resource "aws_security_group" "k8s_cluster" {
  name        = "${var.project_name}-k8s-cluster-sg"
  description = "Security group for k0s cluster nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "k0s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "k0s internal API"
    from_port   = 9443
    to_port     = 9443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "etcd"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "kube-proxy / calico"
    from_port   = 10256
    to_port     = 10256
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Calico VXLAN"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    self        = true
  }

  ingress {
    description = "NodePort range"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-k8s-cluster-sg"
  })
}

# GPU Lab Security Group
resource "aws_security_group" "gpu_lab" {
  name        = "${var.project_name}-gpu-lab-sg"
  description = "Security group for GPU lab instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "All traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-gpu-lab-sg"
  })
}
