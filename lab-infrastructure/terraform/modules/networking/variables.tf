# Variables for Per-Student Networking Module

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "k0rdent-training"
}

variable "engineer_id" {
  description = "Unique identifier for the engineer"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "gpu_az" {
  description = "Availability zone with GPU instance capacity. Empty = auto-select first AZ."
  type        = string
  default     = ""
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
