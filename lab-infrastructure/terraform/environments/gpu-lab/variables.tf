# Variables for GPU Lab Environment

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "k0rdent-training"
}

variable "lab_session_id" {
  description = "Lab session identifier (e.g., 'cohort-2024-q1')"
  type        = string
}

variable "tfstate_bucket" {
  type = string
}

variable "enable_shared_gpu" {
  type    = bool
  default = true
}

variable "enable_advanced_gpu" {
  description = "Enable 8x A100 instance for Lab 3.3"
  type        = bool
  default     = false
}

variable "use_spot_instances" {
  type    = bool
  default = true
}

variable "use_nvidia_ami" {
  type    = bool
  default = true
}

variable "shared_gpu_instance_type" {
  type    = string
  default = "p3.8xlarge"
}

variable "advanced_gpu_instance_type" {
  type    = string
  default = "p4d.24xlarge"
}

variable "engineer_slots" {
  type    = number
  default = 15
}

variable "model_storage_size" {
  type    = number
  default = 500
}

variable "k0s_version" {
  type    = string
  default = "v1.32.4+k0s.0"
}

variable "gpu_operator_version" {
  type    = string
  default = "v25.10.0"
}

variable "tags" {
  type    = map(string)
  default = {}
}
