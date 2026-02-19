# Variables for KubeVirt Lab Environment

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "k0rdent-training"
}

variable "engineer_id" {
  type = string
}

variable "tfstate_bucket" {
  type = string
}

variable "bucket_region" {
  description = "AWS region where the S3 state bucket is located"
  type        = string
}

variable "controller_instance_type" {
  type    = string
  default = "m5.xlarge"
}

variable "worker_instance_type" {
  type    = string
  default = "m5.2xlarge"
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "use_spot_instances" {
  type    = bool
  default = true
}

variable "k0s_version" {
  type    = string
  default = "v1.32.4+k0s.0"
}

variable "kubevirt_version" {
  type    = string
  default = "v1.6.3"
}

variable "cdi_version" {
  type    = string
  default = "v1.61.0"
}

variable "tags" {
  type    = map(string)
  default = {}
}
