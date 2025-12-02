# GPU Lab Environment
# Provisions shared GPU instances for AI workload labs

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}

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
      Project   = "k0rdent-training"
      ManagedBy = "terraform"
    }
  }
}

data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket = var.tfstate_bucket
    key    = "shared/terraform.tfstate"
    region = var.region
  }
}

module "gpu_lab" {
  source = "../../modules/gpu-lab"

  project_name   = var.project_name
  lab_session_id = var.lab_session_id
  region         = var.region

  gpu_subnet_id         = data.terraform_remote_state.shared.outputs.gpu_subnet_id
  security_group_ids    = [data.terraform_remote_state.shared.outputs.gpu_lab_security_group_id]
  instance_profile_name = data.terraform_remote_state.shared.outputs.lab_instance_profile_name

  enable_shared_gpu   = var.enable_shared_gpu
  enable_advanced_gpu = var.enable_advanced_gpu
  use_spot_instances  = var.use_spot_instances
  use_nvidia_ami      = var.use_nvidia_ami

  shared_gpu_instance_type   = var.shared_gpu_instance_type
  advanced_gpu_instance_type = var.advanced_gpu_instance_type
  engineer_slots             = var.engineer_slots
  model_storage_size         = var.model_storage_size

  k0s_version          = var.k0s_version
  gpu_operator_version = var.gpu_operator_version

  artifacts_bucket = data.terraform_remote_state.shared.outputs.artifacts_bucket
  images_bucket    = data.terraform_remote_state.shared.outputs.images_bucket

  tags = var.tags
}

output "shared_gpu_instance_id" {
  value = module.gpu_lab.shared_gpu_instance_id
}

output "shared_gpu_private_ip" {
  value = module.gpu_lab.shared_gpu_private_ip
}

output "advanced_gpu_instance_id" {
  value = module.gpu_lab.advanced_gpu_instance_id
}

output "advanced_gpu_private_ip" {
  value = module.gpu_lab.advanced_gpu_private_ip
}

output "ssh_private_key" {
  value     = module.gpu_lab.ssh_private_key
  sensitive = true
}

output "connection_info" {
  value = module.gpu_lab.connection_info
}

output "gpu_info" {
  value = module.gpu_lab.gpu_info
}
