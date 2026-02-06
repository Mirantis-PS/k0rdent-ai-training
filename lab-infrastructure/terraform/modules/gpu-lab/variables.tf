# Variables for GPU Lab Environment Module

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "k0rdent-training"
}

variable "lab_session_id" {
  description = "Unique identifier for the lab session (e.g., 'cohort-2026-q1')"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "gpu_subnet_id" {
  description = "Subnet ID for GPU instances (must be in AZ with GPU capacity)"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs for instances"
  type        = list(string)
}

variable "instance_profile_name" {
  description = "IAM instance profile name"
  type        = string
}

#------------------------------------------------------------------------------
# Instance Types
#------------------------------------------------------------------------------
variable "shared_gpu_instance_type" {
  description = "Instance type for shared GPU lab (p3.8xlarge = 4x V100)"
  type        = string
  default     = "p3.8xlarge"
}

variable "advanced_gpu_instance_type" {
  description = "Instance type for advanced GPU lab (p4d.24xlarge = 8x A100)"
  type        = string
  default     = "p4d.24xlarge"
}

#------------------------------------------------------------------------------
# Feature Flags
#------------------------------------------------------------------------------
variable "enable_shared_gpu" {
  description = "Enable shared GPU instance (p3.8xlarge)"
  type        = bool
  default     = true
}

variable "enable_advanced_gpu" {
  description = "Enable advanced GPU instance (p4d.24xlarge) for Lab 3.3"
  type        = bool
  default     = false
}

variable "use_spot_instances" {
  description = "Use spot instances for shared GPU (significant cost savings)"
  type        = bool
  default     = true
}

variable "use_nvidia_ami" {
  description = "Use NVIDIA Deep Learning AMI (faster setup, pre-installed drivers)"
  type        = bool
  default     = true
}

variable "spot_max_price" {
  description = "Maximum spot price for GPU instances"
  type        = string
  default     = "" # Empty = on-demand price cap
}

#------------------------------------------------------------------------------
# Capacity
#------------------------------------------------------------------------------
variable "engineer_slots" {
  description = "Number of engineer slots for the shared GPU instance"
  type        = number
  default     = 15
}

variable "model_storage_size" {
  description = "Size of additional EBS volume for models and datasets (GB)"
  type        = number
  default     = 500
}

#------------------------------------------------------------------------------
# Software Versions
#------------------------------------------------------------------------------
variable "k0s_version" {
  description = "k0s version to install"
  type        = string
  default     = "v1.32.4+k0s.0"
}

variable "gpu_operator_version" {
  description = "NVIDIA GPU Operator version (uses calendar versioning YY.MM.PP)"
  type        = string
  default     = "v25.10.0"
}

variable "nvidia_driver_version" {
  description = "NVIDIA driver version"
  type        = string
  default     = "570"
}

variable "cuda_version" {
  description = "CUDA version"
  type        = string
  default     = "12.6"
}

#------------------------------------------------------------------------------
# Storage
#------------------------------------------------------------------------------
variable "artifacts_bucket" {
  description = "S3 bucket for lab artifacts"
  type        = string
}

variable "images_bucket" {
  description = "S3 bucket for OS images"
  type        = string
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
