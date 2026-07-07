# Metal3 Development Environment Module
# Creates EC2 instances with nested virtualization for simulated bare metal provisioning

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
    LabType     = "metal3-dev"
    ManagedBy   = "terraform"
  })

  # Get controller IP regardless of spot vs on-demand
  controller_private_ip = var.use_spot_instances ? (
    length(aws_spot_instance_request.controller_spot) > 0 ? aws_spot_instance_request.controller_spot[0].private_ip : ""
    ) : (
    length(aws_instance.controller) > 0 ? aws_instance.controller[0].private_ip : ""
  )

  # Cloud-init template selection (simple for validation, full for production)
  cloud_init_template = var.use_simple_cloud_init ? "controller-cloud-init-simple.yaml" : "controller-cloud-init.yaml"

  # Pre-compute cloud-init user_data
  controller_user_data = base64encode(templatefile("${path.module}/templates/${local.cloud_init_template}", {
    engineer_id      = var.engineer_id
    k0s_version      = var.k0s_version
    metal3_version   = var.metal3_version
    ironic_version   = var.ironic_version
    worker_count     = var.simulated_worker_count
    artifacts_bucket = var.artifacts_bucket
    images_bucket    = var.images_bucket
    region           = var.region
    ssh_public_key   = tls_private_key.lab.public_key_openssh
  }))
}

#------------------------------------------------------------------------------
# SSH Key Pair
#------------------------------------------------------------------------------
resource "tls_private_key" "lab" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab" {
  key_name   = "${var.project_name}-metal3-${var.engineer_id}"
  public_key = tls_private_key.lab.public_key_openssh

  tags = merge(local.common_tags, {
    Name       = "${var.project_name}-metal3-${var.engineer_id}"
    EngineerID = var.engineer_id
  })
}

#------------------------------------------------------------------------------
# AMI Lookup - Ubuntu 22.04 with metal instance support
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
# Metal3 Controller Instance (On-Demand)
# Runs Ironic, Metal3 operator, and k0s management cluster
# Only created when NOT using spot instances
#------------------------------------------------------------------------------
resource "aws_instance" "controller" {
  count = var.use_spot_instances ? 0 : 1

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

  # Additional storage for VM images
  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = 200
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data_base64 = local.controller_user_data

  # Enforce IMDSv2. k0s + Ironic/Metal3 pods have no legitimate IMDS use
  # (no CCM/CSI; S3 log upload runs as a root host script): hop_limit 1.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.common_tags, {
    Name       = "${var.project_name}-metal3-controller-${var.engineer_id}"
    Role       = "controller"
    EngineerID = var.engineer_id
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

#------------------------------------------------------------------------------
# Simulated Bare Metal Workers (nested VMs via libvirt)
# These are created by cloud-init on the controller using libvirt/QEMU
# The Terraform only provisions the host instance
#------------------------------------------------------------------------------

# Optional: Additional worker host for larger simulations
resource "aws_instance" "worker_host" {
  count = var.additional_worker_hosts

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_host_instance_type
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

  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = 300
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/worker-host-cloud-init.yaml", {
    engineer_id       = var.engineer_id
    controller_ip     = local.controller_private_ip
    worker_host_index = count.index
  }))

  # Enforce IMDSv2. Plain libvirt/QEMU host (no Kubernetes pods): hop_limit 1.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.common_tags, {
    Name       = "${var.project_name}-metal3-worker-host-${var.engineer_id}-${count.index}"
    Role       = "worker-host"
    EngineerID = var.engineer_id
  })

  # Depends on whichever controller type is being used
  depends_on = [aws_instance.controller, aws_spot_instance_request.controller_spot]

  lifecycle {
    ignore_changes = [ami]
  }
}

#------------------------------------------------------------------------------
# Spot Instance Request (optional cost savings)
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

  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = 200
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data_base64 = local.controller_user_data

  # Enforce IMDSv2 (same posture as the on-demand controller): hop_limit 1.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Tags for the spot request itself
  tags = merge(local.common_tags, {
    Name       = "${var.project_name}-metal3-controller-${var.engineer_id}"
    Role       = "controller"
    EngineerID = var.engineer_id
    Owner      = var.engineer_id
  })
}

# Tags for the actual EC2 instance created by spot request
resource "aws_ec2_tag" "controller_spot_name" {
  count       = var.use_spot_instances ? 1 : 0
  resource_id = aws_spot_instance_request.controller_spot[0].spot_instance_id
  key         = "Name"
  value       = "${var.project_name}-metal3-controller-${var.engineer_id}"
}

resource "aws_ec2_tag" "controller_spot_owner" {
  count       = var.use_spot_instances ? 1 : 0
  resource_id = aws_spot_instance_request.controller_spot[0].spot_instance_id
  key         = "Owner"
  value       = var.engineer_id
}

resource "aws_ec2_tag" "controller_spot_engineer_id" {
  count       = var.use_spot_instances ? 1 : 0
  resource_id = aws_spot_instance_request.controller_spot[0].spot_instance_id
  key         = "EngineerID"
  value       = var.engineer_id
}

resource "aws_ec2_tag" "controller_spot_project" {
  count       = var.use_spot_instances ? 1 : 0
  resource_id = aws_spot_instance_request.controller_spot[0].spot_instance_id
  key         = "Project"
  value       = var.project_name
}

resource "aws_ec2_tag" "controller_spot_role" {
  count       = var.use_spot_instances ? 1 : 0
  resource_id = aws_spot_instance_request.controller_spot[0].spot_instance_id
  key         = "Role"
  value       = "controller"
}

resource "aws_ec2_tag" "controller_spot_labtype" {
  count       = var.use_spot_instances ? 1 : 0
  resource_id = aws_spot_instance_request.controller_spot[0].spot_instance_id
  key         = "LabType"
  value       = "metal3-dev"
}

resource "aws_ec2_tag" "controller_spot_environment" {
  count       = var.use_spot_instances ? 1 : 0
  resource_id = aws_spot_instance_request.controller_spot[0].spot_instance_id
  key         = "Environment"
  value       = "metal3-dev"
}

resource "aws_ec2_tag" "controller_spot_managed_by" {
  count       = var.use_spot_instances ? 1 : 0
  resource_id = aws_spot_instance_request.controller_spot[0].spot_instance_id
  key         = "ManagedBy"
  value       = "terraform"
}

#------------------------------------------------------------------------------
# CloudWatch Log Group
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "metal3" {
  name              = "/k0rdent-training/metal3/${var.engineer_id}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    EngineerID = var.engineer_id
  })
}
