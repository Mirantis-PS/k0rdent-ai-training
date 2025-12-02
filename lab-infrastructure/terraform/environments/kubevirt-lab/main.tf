# KubeVirt Lab Environment
# Provisions k0s cluster with KubeVirt for VM workloads

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

module "kubevirt_lab" {
  source = "../../modules/kubevirt-lab"

  project_name = var.project_name
  engineer_id  = var.engineer_id
  region       = var.region

  subnet_id             = data.terraform_remote_state.shared.outputs.private_subnet_ids[0]
  security_group_ids    = [data.terraform_remote_state.shared.outputs.k8s_cluster_security_group_id]
  instance_profile_name = data.terraform_remote_state.shared.outputs.lab_instance_profile_name

  controller_instance_type = var.controller_instance_type
  worker_instance_type     = var.worker_instance_type
  worker_count             = var.worker_count
  use_spot_instances       = var.use_spot_instances

  k0s_version      = var.k0s_version
  kubevirt_version = var.kubevirt_version
  cdi_version      = var.cdi_version

  artifacts_bucket = data.terraform_remote_state.shared.outputs.artifacts_bucket
  images_bucket    = data.terraform_remote_state.shared.outputs.images_bucket

  tags = var.tags
}

output "controller_instance_id" {
  value = module.kubevirt_lab.controller_instance_id
}

output "controller_private_ip" {
  value = module.kubevirt_lab.controller_private_ip
}

output "worker_private_ips" {
  value = module.kubevirt_lab.worker_private_ips
}

output "ssh_private_key" {
  value     = module.kubevirt_lab.ssh_private_key
  sensitive = true
}

output "connection_info" {
  value = module.kubevirt_lab.connection_info
}
