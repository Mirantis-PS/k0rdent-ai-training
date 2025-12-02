# Variables for Metal3 Development Environment Module

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
  description = "Instance type for Metal3 controller (needs nested virtualization support)"
  type        = string
  default     = "m5.2xlarge" # 8 vCPU, 32GB RAM - supports nested virtualization
}

variable "worker_host_instance_type" {
  description = "Instance type for additional worker hosts"
  type        = string
  default     = "m5.xlarge" # 4 vCPU, 16GB RAM
}

variable "additional_worker_hosts" {
  description = "Number of additional worker host instances (0 for single-node setup)"
  type        = number
  default     = 0
}

variable "simulated_worker_count" {
  description = "Number of simulated bare metal workers (VMs on controller)"
  type        = number
  default     = 3
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

variable "metal3_version" {
  description = "Metal3 operator version (CAPM3)"
  type        = string
  default     = "v1.8.0"
}

variable "ironic_version" {
  description = "Ironic version for bare metal provisioning"
  type        = string
  default     = "26.1"
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

variable "use_simple_cloud_init" {
  description = "Use simplified cloud-init (for validation/testing)"
  type        = bool
  default     = false
}
