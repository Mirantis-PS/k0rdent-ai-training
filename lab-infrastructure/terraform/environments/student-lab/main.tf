# Student Lab Environment
# Single Terraform apply creates all resources for one student

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
      Project     = var.project_name
      ManagedBy   = "terraform"
      Owner       = var.engineer_id
      Environment = "student-lab"
    }
  }
}

# --- Networking ---
module "networking" {
  source = "../../modules/networking"

  project_name      = var.project_name
  engineer_id       = var.engineer_id
  vpc_cidr          = var.vpc_cidr
  gpu_az            = var.gpu_az
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  tags              = var.tags
}

# --- Bastion ---
module "bastion" {
  source = "../../modules/bastion"

  project_name      = var.project_name
  engineer_id       = var.engineer_id
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = module.networking.bastion_security_group_id
  tags              = var.tags
}

# --- IAM ---
module "iam" {
  source = "../../modules/iam"

  project_name       = var.project_name
  engineer_id        = var.engineer_id
  region             = var.region
  student_bucket_arn = "arn:aws:s3:::${var.student_bucket}"
  tags               = var.tags
}

# --- k0rdent Management Cluster ---
module "k0rdent_mgmt" {
  source = "../../modules/k0rdent-mgmt"

  project_name = var.project_name
  engineer_id  = var.engineer_id
  region       = var.region

  vpc_id                = module.networking.vpc_id
  subnet_id             = module.networking.private_subnet_ids[0]
  public_subnet_ids     = module.networking.public_subnet_ids
  security_group_ids    = [module.networking.lab_instance_security_group_id]
  instance_profile_name = module.iam.lab_instance_profile_name
  bastion_sg_id         = module.networking.bastion_security_group_id

  node_count       = var.node_count
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  k0s_version           = var.k0s_version
  k0rdent_version       = var.k0rdent_version
  ui_password           = var.ui_password
  flux_version          = var.flux_version
  gateway_api_version   = var.gateway_api_version
  envoy_gateway_version = var.envoy_gateway_version

  artifacts_bucket = var.student_bucket

  cohort_id    = var.cohort_id
  current_week = var.current_week
  ttl_hours    = var.ttl_hours

  tags = var.tags
}

# --- Optional: GPU Lab ---
module "gpu_lab" {
  count  = var.enable_gpu_lab ? 1 : 0
  source = "../../modules/gpu-lab"

  project_name   = var.project_name
  lab_session_id = var.engineer_id
  region         = var.region

  gpu_subnet_id         = module.networking.gpu_subnet_id
  security_group_ids    = [module.networking.gpu_lab_security_group_id]
  instance_profile_name = module.iam.lab_instance_profile_name

  artifacts_bucket = var.student_bucket
  images_bucket    = var.student_bucket

  tags = var.tags
}

# --- Optional: Metal3 ---
module "metal3_dev" {
  count  = var.enable_metal3 ? 1 : 0
  source = "../../modules/metal3-dev"

  project_name = var.project_name
  engineer_id  = var.engineer_id
  region       = var.region

  subnet_id             = module.networking.private_subnet_ids[0]
  security_group_ids    = [module.networking.lab_instance_security_group_id]
  instance_profile_name = module.iam.lab_instance_profile_name

  artifacts_bucket = var.student_bucket
  images_bucket    = var.student_bucket

  tags = var.tags
}

# --- Optional: KubeVirt ---
module "kubevirt_lab" {
  count  = var.enable_kubevirt ? 1 : 0
  source = "../../modules/kubevirt-lab"

  project_name = var.project_name
  engineer_id  = var.engineer_id
  region       = var.region

  subnet_id             = module.networking.private_subnet_ids[0]
  security_group_ids    = [module.networking.k8s_cluster_security_group_id]
  instance_profile_name = module.iam.lab_instance_profile_name

  artifacts_bucket = var.student_bucket
  images_bucket    = var.student_bucket

  tags = var.tags
}
