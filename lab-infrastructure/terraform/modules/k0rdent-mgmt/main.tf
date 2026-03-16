# k0rdent Management Cluster Module
# Creates a 3-node k0s cluster for k0rdent AI management

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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

#------------------------------------------------------------------------------
# Generate random UI password if not provided
#------------------------------------------------------------------------------
resource "random_password" "ui_password" {
  length  = 32
  special = false # Avoid special chars that break YAML/shell escaping in Helm
}

locals {
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = "lab"
    LabType     = "k0rdent-mgmt"
    ManagedBy   = "terraform"
    EngineerID  = var.engineer_id
    CohortID    = var.cohort_id
    Week        = var.current_week
    TTLHours    = var.ttl_hours
    AutoStop    = "true"
  })

  # Minimal tags for S3 objects (AWS S3 has 10-tag limit, provider default_tags count toward this)
  s3_object_tags = {
    EngineerID = var.engineer_id
    LabType    = "k0rdent-mgmt"
  }

  # Use provided password or generate random one
  effective_ui_password = var.ui_password != "" ? var.ui_password : random_password.ui_password.result

  # Generate node names
  node_names = [for i in range(var.node_count) : "${var.project_name}-mgmt-${var.engineer_id}-${i}"]

  # Cloud-init user data
  node_user_data = base64encode(templatefile("${path.module}/templates/mgmt-cloud-init.yaml", {
    engineer_id      = var.engineer_id
    k0s_version      = var.k0s_version
    k0rdent_version  = var.k0rdent_version
    ui_password      = local.effective_ui_password
    flux_version     = var.flux_version
    artifacts_bucket = var.artifacts_bucket
    region           = var.region
    ssh_public_key   = tls_private_key.mgmt.public_key_openssh
  }))

  # Generate k0sctl configuration
  k0sctl_yaml = templatefile("${path.module}/templates/k0sctl.yaml.tpl", {
    cluster_name = "k0rdent-mgmt-${var.engineer_id}"
    k0s_version  = var.k0s_version
    node_ips     = aws_instance.mgmt_node[*].private_ip
    ssh_user     = "ubuntu"
    ssh_key_path = "~/.k0rdent-lab/${var.engineer_id}/ssh_key"
  })
}

#------------------------------------------------------------------------------
# SSH Key Pair
#------------------------------------------------------------------------------
resource "tls_private_key" "mgmt" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "mgmt" {
  key_name   = "${var.project_name}-mgmt-${var.engineer_id}"
  public_key = tls_private_key.mgmt.public_key_openssh

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-mgmt-${var.engineer_id}"
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

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

#------------------------------------------------------------------------------
# Security Group for Management Cluster
#------------------------------------------------------------------------------
resource "aws_security_group" "mgmt_cluster" {
  name        = "${var.project_name}-mgmt-cluster-${var.engineer_id}"
  description = "Security group for k0rdent management cluster"
  vpc_id      = var.vpc_id

  # SSH from bastion
  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_sg_id]
  }

  # k0s API server
  ingress {
    description = "k0s API server from VPC"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # k0s join API
  ingress {
    description = "k0s join API"
    from_port   = 9443
    to_port     = 9443
    protocol    = "tcp"
    self        = true
  }

  # etcd
  ingress {
    description = "etcd client"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  # Kubelet API
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # konnectivity
  ingress {
    description = "konnectivity"
    from_port   = 8132
    to_port     = 8133
    protocol    = "tcp"
    self        = true
  }

  # All internal traffic between cluster nodes
  ingress {
    description = "All internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # NLB health checks and traffic to k0rdent UI NodePort
  ingress {
    description = "k0rdent UI via NLB"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-mgmt-cluster-${var.engineer_id}"
  })
}

#------------------------------------------------------------------------------
# Management Cluster Nodes (On-Demand for reliability)
#------------------------------------------------------------------------------
resource "aws_instance" "mgmt_node" {
  count = var.node_count

  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  key_name             = aws_key_pair.mgmt.key_name
  subnet_id            = var.subnet_id
  iam_instance_profile = var.instance_profile_name

  vpc_security_group_ids = concat(
    var.security_group_ids,
    [aws_security_group.mgmt_cluster.id]
  )

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    encrypted             = true
  }

  user_data_base64 = local.node_user_data

  tags = merge(local.common_tags, {
    Name      = local.node_names[count.index]
    Role      = count.index == 0 ? "controller-primary" : "controller"
    NodeIndex = count.index
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

#------------------------------------------------------------------------------
# CloudWatch Log Group
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "mgmt_cluster" {
  name              = "/k0rdent-training/mgmt/${var.engineer_id}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-mgmt-logs-${var.engineer_id}"
  })
}

#------------------------------------------------------------------------------
# Network Load Balancer for k0rdent UI
#------------------------------------------------------------------------------
resource "aws_lb" "k0rdent_ui" {
  name               = "${var.project_name}-ui-${var.engineer_id}"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ui-${var.engineer_id}"
  })
}

resource "aws_lb_target_group" "k0rdent_ui" {
  name     = "${var.project_name}-ui-${var.engineer_id}"
  port     = 30080
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    protocol            = "TCP"
    port                = 30080
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ui-tg-${var.engineer_id}"
  })
}

resource "aws_lb_listener" "k0rdent_ui" {
  load_balancer_arn = aws_lb.k0rdent_ui.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k0rdent_ui.arn
  }
}

resource "aws_lb_target_group_attachment" "k0rdent_ui" {
  count            = var.node_count
  target_group_arn = aws_lb_target_group.k0rdent_ui.arn
  target_id        = aws_instance.mgmt_node[count.index].id
  port             = 30080
}

#------------------------------------------------------------------------------
# Store SSH key in S3 for retrieval by provisioning scripts
#------------------------------------------------------------------------------
resource "aws_s3_object" "ssh_private_key" {
  bucket       = var.artifacts_bucket
  key          = "ssh-keys/${var.engineer_id}/mgmt/id_ed25519"
  content      = tls_private_key.mgmt.private_key_openssh
  content_type = "text/plain"

  server_side_encryption = "AES256"

  tags = merge(local.s3_object_tags, {
    Name = "ssh-key-${var.engineer_id}-mgmt"
  })
}

resource "aws_s3_object" "ssh_public_key" {
  bucket       = var.artifacts_bucket
  key          = "ssh-keys/${var.engineer_id}/mgmt/id_ed25519.pub"
  content      = tls_private_key.mgmt.public_key_openssh
  content_type = "text/plain"

  tags = merge(local.s3_object_tags, {
    Name = "ssh-pubkey-${var.engineer_id}-mgmt"
  })
}

#------------------------------------------------------------------------------
# Store k0sctl configuration in S3
#------------------------------------------------------------------------------
resource "aws_s3_object" "k0sctl_config" {
  bucket       = var.artifacts_bucket
  key          = "k0sctl/${var.engineer_id}/k0sctl.yaml"
  content      = local.k0sctl_yaml
  content_type = "text/yaml"

  tags = merge(local.s3_object_tags, {
    Name = "k0sctl-${var.engineer_id}"
  })
}
