# Variables for Shared Infrastructure Environment

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

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
  description = "Availability zone with GPU instance capacity"
  type        = string
  default     = "us-east-1a"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion"
  type        = list(string)
  default     = [] # Set via tfvars
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

# Bastion Configuration
variable "bastion_instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "bastion_use_elastic_ip" {
  description = "Assign Elastic IP for stable bastion address"
  type        = bool
  default     = true
}

variable "bastion_additional_ssh_keys" {
  description = "Additional SSH public keys for bastion access"
  type        = list(string)
  default     = []
}
