# Metal3 Development Environment
# Provisions Metal3 dev instances for individual engineers

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
      Environment = "metal3-dev"
    }
  }
}

# Get shared infrastructure outputs
data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket = var.tfstate_bucket
    key    = "${var.region}/shared/terraform.tfstate"
    region = var.bucket_region
  }
}

module "metal3_dev" {
  source = "../../modules/metal3-dev"

  project_name = var.project_name
  engineer_id  = var.engineer_id
  region       = var.region

  subnet_id             = data.terraform_remote_state.shared.outputs.private_subnet_ids[0]
  security_group_ids    = [data.terraform_remote_state.shared.outputs.lab_instance_security_group_id]
  instance_profile_name = data.terraform_remote_state.shared.outputs.lab_instance_profile_name

  controller_instance_type = var.controller_instance_type
  simulated_worker_count   = var.simulated_worker_count
  use_spot_instances       = var.use_spot_instances

  k0s_version    = var.k0s_version
  metal3_version = var.metal3_version

  artifacts_bucket = data.terraform_remote_state.shared.outputs.artifacts_bucket
  images_bucket    = data.terraform_remote_state.shared.outputs.images_bucket

  use_simple_cloud_init = var.use_simple_cloud_init

  tags = var.tags
}

# Outputs
output "controller_instance_id" {
  value = module.metal3_dev.controller_instance_id
}

output "controller_private_ip" {
  value = module.metal3_dev.controller_private_ip
}

output "ssh_private_key" {
  value     = module.metal3_dev.ssh_private_key
  sensitive = true
}

output "connection_info" {
  value = module.metal3_dev.connection_info
}
