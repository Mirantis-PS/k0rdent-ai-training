# Variables for KubeVirt Lab Environment Module

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "k0rdent-training"
}

variable "engineer_id" {
  description = "Unique identifier for the engineer (e.g., 'engineer-01')"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "subnet_id" {
  description = "Subnet ID for instances"
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

variable "controller_instance_type" {
  description = "Instance type for k0s controller"
  type        = string
  default     = "m5.xlarge" # 4 vCPU, 16GB RAM
}

variable "worker_instance_type" {
  description = "Instance type for k0s workers (needs nested virtualization for KubeVirt)"
  type        = string
  default     = "m5.2xlarge" # 8 vCPU, 32GB RAM
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "worker_storage_size" {
  description = "Additional storage size for workers (GB) for VM images"
  type        = number
  default     = 100
}

variable "use_spot_instances" {
  description = "Use spot instances for cost savings"
  type        = bool
  default     = true
}

variable "spot_max_price" {
  description = "Maximum spot price (leave empty for on-demand price)"
  type        = string
  default     = ""
}

variable "k0s_version" {
  description = "k0s version to install"
  type        = string
  default     = "v1.32.4+k0s.0"
}

variable "kubevirt_version" {
  description = "KubeVirt version"
  type        = string
  default     = "v1.6.3"
}

variable "cdi_version" {
  description = "Containerized Data Importer version"
  type        = string
  default     = "v1.61.0"
}

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
