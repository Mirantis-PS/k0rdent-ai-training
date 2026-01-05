# Variables for k0rdent Management Cluster Module

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

variable "vpc_id" {
  description = "VPC ID for the management cluster"
  type        = string
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

variable "bastion_sg_id" {
  description = "Bastion security group ID for SSH access"
  type        = string
}

#------------------------------------------------------------------------------
# Cluster Configuration
#------------------------------------------------------------------------------

variable "node_count" {
  description = "Number of management cluster nodes (should be odd for HA: 1, 3, 5)"
  type        = number
  default     = 3

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 5
    error_message = "Node count must be between 1 and 5."
  }
}

variable "instance_type" {
  description = "EC2 instance type for management cluster nodes"
  type        = string
  default     = "t3.xlarge" # 4 vCPU, 16GB RAM
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 100
}

#------------------------------------------------------------------------------
# k0s and k0rdent Configuration
#------------------------------------------------------------------------------

variable "k0s_version" {
  description = "k0s version to install"
  type        = string
  default     = "v1.32.4+k0s.0"
}

variable "k0rdent_version" {
  description = "k0rdent Enterprise version to install"
  type        = string
  default     = "1.2.1"
}

variable "ui_password" {
  description = "Password for k0rdent UI. If empty, a random password will be generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "flux_version" {
  description = "Flux CD version"
  type        = string
  default     = "v2.4.0"
}

#------------------------------------------------------------------------------
# S3 Buckets
#------------------------------------------------------------------------------

variable "artifacts_bucket" {
  description = "S3 bucket for lab artifacts"
  type        = string
}

variable "images_bucket" {
  description = "S3 bucket for OS images"
  type        = string
}

variable "tfstate_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

#------------------------------------------------------------------------------
# Git Repository Configuration
#------------------------------------------------------------------------------

variable "git_repo_url" {
  description = "Git repository URL for Flux (template: https://git.internal/{engineer}/k0rdent-lab)"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# TTL and Tagging
#------------------------------------------------------------------------------

variable "ttl_hours" {
  description = "Time to live in hours before auto-termination"
  type        = number
  default     = 8
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

variable "current_week" {
  description = "Current training week (1-6)"
  type        = number
  default     = 1
}

variable "cohort_id" {
  description = "Training cohort identifier"
  type        = string
  default     = "cohort-01"
}
