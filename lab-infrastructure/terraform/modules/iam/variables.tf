# Variables for Per-Student IAM Module

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "k0rdent-training"
}

variable "engineer_id" {
  description = "Unique identifier for the engineer"
  type        = string
}

variable "region" {
  description = "AWS region (used in IAM role names for uniqueness)"
  type        = string
}

variable "student_bucket_arn" {
  description = "ARN of the student's S3 bucket (for tfstate, images, artifacts)"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
