# KubeVirt Lab Environment Module
# Creates EC2 instances with k0s cluster and KubeVirt for VM workloads

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
    LabType     = "kubevirt"
    ManagedBy   = "terraform"
  })

  # Calculate total nodes
  total_nodes = 1 + var.worker_count
}

#------------------------------------------------------------------------------
# SSH Key Pair
#------------------------------------------------------------------------------
resource "tls_private_key" "lab" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab" {
  key_name   = "${var.project_name}-kubevirt-${var.engineer_id}"
  public_key = tls_private_key.lab.public_key_openssh

  tags = merge(local.common_tags, {
    Name       = "${var.project_name}-kubevirt-${var.engineer_id}"
    EngineerID = var.engineer_id
  })
}

#------------------------------------------------------------------------------
# AMI Lookup - Ubuntu 22.04
#------------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#------------------------------------------------------------------------------
# k0s Controller Node
#------------------------------------------------------------------------------
resource "aws_instance" "controller" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.controller_instance_type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/controller-cloud-init.yaml", {
    engineer_id      = var.engineer_id
    k0s_version      = var.k0s_version
    kubevirt_version = var.kubevirt_version
    cdi_version      = var.cdi_version
    node_role        = "controller"
    controller_ip    = "" # Will be set post-creation
    artifacts_bucket = var.artifacts_bucket
    images_bucket    = var.images_bucket
    region           = var.region
    worker_count     = var.worker_count
  }))

  tags = merge(local.common_tags, {
    Name       = "${var.project_name}-kubevirt-controller-${var.engineer_id}"
    Role       = "controller"
    EngineerID = var.engineer_id
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

#------------------------------------------------------------------------------
# k0s Worker Nodes
#------------------------------------------------------------------------------
resource "aws_instance" "worker" {
  count = var.worker_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # Additional storage for VM images
  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = var.worker_storage_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/worker-cloud-init.yaml", {
    engineer_id   = var.engineer_id
    k0s_version   = var.k0s_version
    node_role     = "worker"
    controller_ip = aws_instance.controller.private_ip
    worker_index  = count.index
    region        = var.region
  }))

  tags = merge(local.common_tags, {
    Name       = "${var.project_name}-kubevirt-worker-${var.engineer_id}-${count.index}"
    Role       = "worker"
    EngineerID = var.engineer_id
  })

  depends_on = [aws_instance.controller]

  lifecycle {
    ignore_changes = [ami]
  }
}

#------------------------------------------------------------------------------
# Spot Instance Requests (optional)
#------------------------------------------------------------------------------
resource "aws_spot_instance_request" "controller_spot" {
  count = var.use_spot_instances ? 1 : 0

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.controller_instance_type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name

  spot_price           = var.spot_max_price
  wait_for_fulfillment = true
  spot_type            = "one-time"

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/controller-cloud-init.yaml", {
    engineer_id      = var.engineer_id
    k0s_version      = var.k0s_version
    kubevirt_version = var.kubevirt_version
    cdi_version      = var.cdi_version
    node_role        = "controller"
    controller_ip    = ""
    artifacts_bucket = var.artifacts_bucket
    images_bucket    = var.images_bucket
    region           = var.region
    worker_count     = var.worker_count
  }))

  tags = merge(local.common_tags, {
    Name       = "${var.project_name}-kubevirt-controller-spot-${var.engineer_id}"
    Role       = "controller"
    EngineerID = var.engineer_id
  })
}

resource "aws_spot_instance_request" "worker_spot" {
  count = var.use_spot_instances ? var.worker_count : 0

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name

  spot_price           = var.spot_max_price
  wait_for_fulfillment = true
  spot_type            = "one-time"

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = var.worker_storage_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/worker-cloud-init.yaml", {
    engineer_id   = var.engineer_id
    k0s_version   = var.k0s_version
    node_role     = "worker"
    controller_ip = var.use_spot_instances ? aws_spot_instance_request.controller_spot[0].private_ip : aws_instance.controller.private_ip
    worker_index  = count.index
    region        = var.region
  }))

  tags = merge(local.common_tags, {
    Name       = "${var.project_name}-kubevirt-worker-spot-${var.engineer_id}-${count.index}"
    Role       = "worker"
    EngineerID = var.engineer_id
  })

  depends_on = [aws_spot_instance_request.controller_spot]
}

#------------------------------------------------------------------------------
# CloudWatch Log Group
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "kubevirt" {
  name              = "/k0rdent-training/kubevirt/${var.engineer_id}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    EngineerID = var.engineer_id
  })
}
