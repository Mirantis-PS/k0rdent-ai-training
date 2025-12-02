# Variables for Metal3 Development Environment

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "k0rdent-training"
}

variable "engineer_id" {
  description = "Unique identifier for the engineer (e.g., 'engineer-01')"
  type        = string
}

variable "tfstate_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "controller_instance_type" {
  description = "Instance type for controller"
  type        = string
  default     = "m5.2xlarge"
}

variable "simulated_worker_count" {
  description = "Number of simulated bare metal workers"
  type        = number
  default     = 3
}

variable "use_spot_instances" {
  description = "Use spot instances"
  type        = bool
  default     = true
}

variable "k0s_version" {
  description = "k0s version"
  type        = string
  default     = "v1.32.4+k0s.0"
}

variable "metal3_version" {
  description = "Metal3 version"
  type        = string
  default     = "v1.8.0"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
