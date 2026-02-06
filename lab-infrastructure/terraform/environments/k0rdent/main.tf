# k0rdent Enterprise Management Cluster Environment
# Provisions k0s + k0rdent Enterprise for individual engineers

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    # Configure via backend config file or CLI
  }

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

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "k0rdent-training"
      ManagedBy   = "terraform"
      Owner       = var.engineer_id
      Environment = "k0rdent-mgmt"
    }
  }
}

# Get shared infrastructure outputs
data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket = var.tfstate_bucket
    key    = "shared/terraform.tfstate"
    region = var.region
  }
}

module "k0rdent_mgmt" {
  source = "../../modules/k0rdent-mgmt"

  project_name = var.project_name
  engineer_id  = var.engineer_id
  region       = var.region

  vpc_id                = data.terraform_remote_state.shared.outputs.vpc_id
  subnet_id             = data.terraform_remote_state.shared.outputs.private_subnet_ids[0]
  security_group_ids    = [data.terraform_remote_state.shared.outputs.lab_instance_security_group_id]
  instance_profile_name = data.terraform_remote_state.shared.outputs.lab_instance_profile_name
  bastion_sg_id         = data.terraform_remote_state.shared.outputs.bastion_security_group_id

  # Cluster configuration
  node_count       = var.node_count
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  # k0rdent configuration
  k0s_version     = var.k0s_version
  k0rdent_version = var.k0rdent_version
  ui_password     = var.ui_password
  flux_version    = var.flux_version

  # S3 buckets
  artifacts_bucket = data.terraform_remote_state.shared.outputs.artifacts_bucket
  images_bucket    = data.terraform_remote_state.shared.outputs.images_bucket
  tfstate_bucket   = var.tfstate_bucket

  # Training metadata
  cohort_id    = var.cohort_id
  current_week = var.current_week
  ttl_hours    = var.ttl_hours

  tags = var.tags
}

# Outputs
output "mgmt_node_ids" {
  description = "Instance IDs of management cluster nodes"
  value       = module.k0rdent_mgmt.node_instance_ids
}

output "mgmt_node_private_ips" {
  description = "Private IPs of management cluster nodes"
  value       = module.k0rdent_mgmt.node_private_ips
}

output "primary_node_private_ip" {
  description = "Private IP of primary management node"
  value       = module.k0rdent_mgmt.primary_node_ip
}

output "ssh_private_key" {
  description = "SSH private key for accessing nodes"
  value       = module.k0rdent_mgmt.ssh_private_key
  sensitive   = true
}

output "connection_info" {
  description = "Connection instructions"
  value       = module.k0rdent_mgmt.connection_info
}

output "k0rdent_ui_info" {
  description = "k0rdent UI access information"
  value = <<-EOT
    k0rdent Enterprise UI:
    1. Connect to management node: ./lab-connect.sh k0rdent ${var.engineer_id}
    2. Run: kubectl port-forward svc/kcm-k0rdent-ui -n kcm-system 8080:3000
    3. Open: http://localhost:8080
    4. Run: terraform output ui_password
  EOT
}

output "ui_password" {
  description = "k0rdent UI password"
  value       = module.k0rdent_mgmt.ui_password
  sensitive   = true
}
