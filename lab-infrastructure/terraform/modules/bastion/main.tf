# Bastion Host Module
# Provides secure SSH jump access to lab environments

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = "lab"
    Role        = "bastion"
    ManagedBy   = "terraform"
  })
}

#------------------------------------------------------------------------------
# SSH Key Pair
#------------------------------------------------------------------------------
resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = "${var.project_name}-bastion"
  public_key = tls_private_key.bastion.public_key_openssh

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-bastion"
  })
}

#------------------------------------------------------------------------------
# AMI Lookup
#------------------------------------------------------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#------------------------------------------------------------------------------
# Bastion Instance
#------------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.bastion.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 30 # AL2023 AMI requires minimum 30GB
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/bastion-cloud-init.yaml", {
    project_name    = var.project_name
    ssh_public_keys = var.additional_ssh_keys
  }))

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-bastion"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

#------------------------------------------------------------------------------
# Elastic IP (optional, for stable DNS)
#------------------------------------------------------------------------------
resource "aws_eip" "bastion" {
  count = var.use_elastic_ip ? 1 : 0

  instance = aws_instance.bastion.id
  domain   = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-bastion-eip"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Logs
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "bastion" {
  name              = "/k0rdent-training/bastion"
  retention_in_days = 7

  tags = local.common_tags
}
