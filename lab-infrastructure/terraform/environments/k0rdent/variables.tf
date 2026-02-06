# Variables for k0rdent Enterprise Environment

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "k0rdent-training"
}

variable "engineer_id" {
  description = "Unique identifier for the engineer"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "tfstate_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

#------------------------------------------------------------------------------
# Cluster Configuration
#------------------------------------------------------------------------------

variable "node_count" {
  description = "Number of management cluster nodes (1 for single-node, 3 for HA)"
  type        = number
  default     = 1  # Single-node for lab simplicity

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 5
    error_message = "Node count must be between 1 and 5."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.xlarge"  # 4 vCPU, 16GB RAM - good for k0rdent
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 100
}

#------------------------------------------------------------------------------
# k0rdent Configuration
#------------------------------------------------------------------------------

variable "k0s_version" {
  description = "k0s version"
  type        = string
  default     = "v1.32.4+k0s.0"
}

variable "k0rdent_version" {
  description = "k0rdent Enterprise version"
  type        = string
  default     = "1.2.1"
}

variable "ui_password" {
  description = "k0rdent UI password. If empty, a random password will be generated."
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
# Training Metadata
#------------------------------------------------------------------------------

variable "cohort_id" {
  description = "Training cohort ID"
  type        = string
  default     = "cohort-01"
}

variable "current_week" {
  description = "Current training week (1-6)"
  type        = number
  default     = 1
}

variable "ttl_hours" {
  description = "Time to live in hours"
  type        = number
  default     = 8
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
