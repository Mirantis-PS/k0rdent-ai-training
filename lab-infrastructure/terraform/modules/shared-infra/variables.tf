# Variables for Shared Infrastructure Module

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "k0rdent-training"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "gpu_az" {
  description = "Availability zone with GPU instance capacity (P3/P4)"
  type        = string
  default     = "eu-west-1a"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict in production
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
