# Variables for Per-Student Lab Environment

# Core
variable "engineer_id" {
  description = "Unique identifier for the engineer (e.g., 'crusu', 'john-doe')"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "k0rdent-training"
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "student_bucket" {
  description = "S3 bucket name for this student (created by the provisioning script)"
  type        = string
}

# Networking
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "gpu_az" {
  description = "Availability zone for GPU instances. Empty = auto-select."
  type        = string
  default     = ""
}

# k0rdent cluster
variable "node_count" {
  description = "Number of management cluster nodes (1 for lab, 3 for HA)"
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "EC2 instance type for management nodes"
  type        = string
  default     = "t3.2xlarge"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 100
}

variable "k0s_version" {
  description = "k0s version"
  type        = string
  default     = "v1.35.4+k0s.0"
}

variable "k0rdent_version" {
  description = "k0rdent Enterprise version"
  type        = string
  default     = "1.3.1"
}

variable "ui_password" {
  description = "k0rdent UI password (empty = auto-generate)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "flux_version" {
  description = "Flux CD version"
  type        = string
  default     = "v2.4.0"
}

variable "gateway_api_version" {
  description = "Gateway API CRD version"
  type        = string
  default     = "v1.2.1"
}

variable "envoy_gateway_version" {
  description = "Envoy Gateway Helm chart version"
  type        = string
  default     = "v1.2.6"
}

# Training metadata
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

# Optional lab environments (enabled for later weeks)
variable "enable_gpu_lab" {
  description = "Enable GPU lab environment"
  type        = bool
  default     = false
}

variable "enable_metal3" {
  description = "Enable Metal3 dev environment"
  type        = bool
  default     = false
}

variable "enable_kubevirt" {
  description = "Enable KubeVirt lab environment"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
