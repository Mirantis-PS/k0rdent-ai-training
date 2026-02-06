# Shared Infrastructure Environment
# Provisions VPC, S3 buckets, and IAM roles shared by all lab environments

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    # Configure via backend config file or CLI
    # bucket = "k0rdent-training-tfstate-ACCOUNT_ID"
    # key    = "shared/terraform.tfstate"
    # region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "k0rdent-training"
      ManagedBy   = "terraform"
      Owner       = var.owner
      Environment = "shared"
    }
  }
}

module "shared_infra" {
  source = "../../modules/shared-infra"

  project_name      = var.project_name
  vpc_cidr          = var.vpc_cidr
  gpu_az            = var.gpu_az
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  tags              = var.tags
}

# Bastion Host
module "bastion" {
  source = "../../modules/bastion"

  project_name        = var.project_name
  subnet_id           = module.shared_infra.public_subnet_ids[0]
  security_group_id   = module.shared_infra.bastion_security_group_id
  instance_type       = var.bastion_instance_type
  use_elastic_ip      = var.bastion_use_elastic_ip
  additional_ssh_keys = var.bastion_additional_ssh_keys
  tags                = var.tags
}

# Outputs
output "vpc_id" {
  value = module.shared_infra.vpc_id
}

output "public_subnet_ids" {
  value = module.shared_infra.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.shared_infra.private_subnet_ids
}

output "gpu_subnet_id" {
  value = module.shared_infra.gpu_subnet_id
}

output "bastion_security_group_id" {
  value = module.shared_infra.bastion_security_group_id
}

output "lab_instance_security_group_id" {
  value = module.shared_infra.lab_instance_security_group_id
}

output "k8s_cluster_security_group_id" {
  value = module.shared_infra.k8s_cluster_security_group_id
}

output "gpu_lab_security_group_id" {
  value = module.shared_infra.gpu_lab_security_group_id
}

output "tfstate_bucket" {
  value = module.shared_infra.tfstate_bucket
}

output "images_bucket" {
  value = module.shared_infra.images_bucket
}

output "artifacts_bucket" {
  value = module.shared_infra.artifacts_bucket
}

output "lab_instance_profile_name" {
  value = module.shared_infra.lab_instance_profile_name
}

output "nat_gateway_ip" {
  value = module.shared_infra.nat_gateway_ip
}

output "bastion_public_ip" {
  value = module.bastion.public_ip
}

output "bastion_ssh_private_key" {
  value     = module.bastion.ssh_private_key
  sensitive = true
}

output "bastion_connection_string" {
  value = module.bastion.connection_string
}
