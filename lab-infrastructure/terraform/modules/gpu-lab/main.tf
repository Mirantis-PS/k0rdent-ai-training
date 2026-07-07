# GPU Lab Environment Module
# Creates shared GPU instances for k0rdent AI training labs
# Supports p3.8xlarge (4x V100) for standard labs and p4d.24xlarge (8x A100) for advanced labs

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
    LabType     = "gpu"
    ManagedBy   = "terraform"
  })
}

#------------------------------------------------------------------------------
# SSH Key Pair
#------------------------------------------------------------------------------
resource "tls_private_key" "lab" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab" {
  key_name   = "${var.project_name}-gpu-${var.lab_session_id}"
  public_key = tls_private_key.lab.public_key_openssh

  tags = merge(local.common_tags, {
    Name         = "${var.project_name}-gpu-${var.lab_session_id}"
    LabSessionID = var.lab_session_id
  })
}

#------------------------------------------------------------------------------
# AMI Lookup - NVIDIA Deep Learning AMI
#------------------------------------------------------------------------------
data "aws_ami" "nvidia_dl" {
  most_recent = true
  owners      = ["898082745236"] # AWS Marketplace - NVIDIA

  filter {
    name   = "name"
    values = ["Deep Learning*AMI GPU PyTorch*Ubuntu 22.04*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Fallback to Ubuntu with manual NVIDIA driver install
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
# Shared GPU Instance (p3.8xlarge - 4x V100)
# This instance is shared among engineers during a lab session
#------------------------------------------------------------------------------
resource "aws_instance" "gpu_shared" {
  count = var.enable_shared_gpu ? 1 : 0

  ami                    = var.use_nvidia_ami ? data.aws_ami.nvidia_dl.id : data.aws_ami.ubuntu.id
  instance_type          = var.shared_gpu_instance_type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = var.gpu_subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name

  root_block_device {
    volume_size           = 200
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # Additional storage for models and datasets
  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = var.model_storage_size
    volume_type           = "gp3"
    iops                  = 16000
    throughput            = 1000
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/gpu-cloud-init.yaml", {
    lab_session_id        = var.lab_session_id
    k0s_version           = var.k0s_version
    gpu_operator_version  = var.gpu_operator_version
    nvidia_driver_version = var.nvidia_driver_version
    cuda_version          = var.cuda_version
    artifacts_bucket      = var.artifacts_bucket
    images_bucket         = var.images_bucket
    region                = var.region
    instance_type         = var.shared_gpu_instance_type
    use_nvidia_ami        = var.use_nvidia_ami
    engineer_slots        = var.engineer_slots
  }))

  # Enforce IMDSv2. Single-node k0s GPU stack (GPU operator / inference pods)
  # has no legitimate IMDS use — no CCM/CSI, S3 log upload is a root host
  # script: hop_limit 1 keeps pod-network workloads away from instance creds.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.common_tags, {
    Name         = "${var.project_name}-gpu-shared-${var.lab_session_id}"
    Role         = "gpu-shared"
    LabSessionID = var.lab_session_id
    GPUType      = "V100"
    GPUCount     = "4"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

#------------------------------------------------------------------------------
# Advanced GPU Instance (p4d.24xlarge - 8x A100) - On-demand for Lab 3.3
# Only created when explicitly needed for 8-GPU NVLink labs
#------------------------------------------------------------------------------
resource "aws_instance" "gpu_advanced" {
  count = var.enable_advanced_gpu ? 1 : 0

  ami                    = var.use_nvidia_ami ? data.aws_ami.nvidia_dl.id : data.aws_ami.ubuntu.id
  instance_type          = var.advanced_gpu_instance_type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = var.gpu_subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name

  root_block_device {
    volume_size           = 500
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # High-performance storage for large models
  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = 1000
    volume_type           = "gp3"
    iops                  = 16000
    throughput            = 1000
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/gpu-advanced-cloud-init.yaml", {
    lab_session_id        = var.lab_session_id
    k0s_version           = var.k0s_version
    gpu_operator_version  = var.gpu_operator_version
    nvidia_driver_version = var.nvidia_driver_version
    cuda_version          = var.cuda_version
    artifacts_bucket      = var.artifacts_bucket
    images_bucket         = var.images_bucket
    region                = var.region
    instance_type         = var.advanced_gpu_instance_type
    use_nvidia_ami        = var.use_nvidia_ami
  }))

  # Enforce IMDSv2. Same single-node k0s GPU stack as gpu_shared: hop_limit 1.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.common_tags, {
    Name         = "${var.project_name}-gpu-advanced-${var.lab_session_id}"
    Role         = "gpu-advanced"
    LabSessionID = var.lab_session_id
    GPUType      = "A100"
    GPUCount     = "8"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

#------------------------------------------------------------------------------
# Spot Instance Request for Shared GPU (cost savings)
#------------------------------------------------------------------------------
resource "aws_spot_instance_request" "gpu_shared_spot" {
  count = var.enable_shared_gpu && var.use_spot_instances ? 1 : 0

  ami                    = var.use_nvidia_ami ? data.aws_ami.nvidia_dl.id : data.aws_ami.ubuntu.id
  instance_type          = var.shared_gpu_instance_type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = var.gpu_subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name

  spot_price           = var.spot_max_price
  wait_for_fulfillment = true
  spot_type            = "one-time"

  root_block_device {
    volume_size           = 200
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = var.model_storage_size
    volume_type           = "gp3"
    iops                  = 16000
    throughput            = 1000
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/gpu-cloud-init.yaml", {
    lab_session_id        = var.lab_session_id
    k0s_version           = var.k0s_version
    gpu_operator_version  = var.gpu_operator_version
    nvidia_driver_version = var.nvidia_driver_version
    cuda_version          = var.cuda_version
    artifacts_bucket      = var.artifacts_bucket
    images_bucket         = var.images_bucket
    region                = var.region
    instance_type         = var.shared_gpu_instance_type
    use_nvidia_ami        = var.use_nvidia_ami
    engineer_slots        = var.engineer_slots
  }))

  # Enforce IMDSv2 (same posture as the on-demand GPU instance): hop_limit 1.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.common_tags, {
    Name         = "${var.project_name}-gpu-shared-spot-${var.lab_session_id}"
    Role         = "gpu-shared"
    LabSessionID = var.lab_session_id
    GPUType      = "V100"
    GPUCount     = "4"
  })
}

#------------------------------------------------------------------------------
# Placement Group for GPU instances (cluster placement)
#------------------------------------------------------------------------------
resource "aws_placement_group" "gpu" {
  name     = "${var.project_name}-gpu-${var.lab_session_id}"
  strategy = "cluster"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-gpu-placement-${var.lab_session_id}"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Log Group
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "gpu" {
  name              = "/k0rdent-training/gpu/${var.lab_session_id}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    LabSessionID = var.lab_session_id
  })
}

#------------------------------------------------------------------------------
# CloudWatch Alarms for GPU utilization
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "gpu_utilization_low" {
  count = var.enable_shared_gpu ? 1 : 0

  alarm_name          = "${var.project_name}-gpu-low-util-${var.lab_session_id}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 6
  metric_name         = "GPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 10
  alarm_description   = "GPU utilization below 10% for 30 minutes"

  dimensions = {
    InstanceId = var.use_spot_instances ? aws_spot_instance_request.gpu_shared_spot[0].spot_instance_id : aws_instance.gpu_shared[0].id
  }

  tags = local.common_tags
}
