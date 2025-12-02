# Variables for Bastion Host Module

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "k0rdent-training"
}

variable "subnet_id" {
  description = "Public subnet ID for bastion"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for bastion"
  type        = string
}

variable "instance_type" {
  description = "Instance type for bastion"
  type        = string
  default     = "t3.small"  # t3.micro is too resource-constrained for SSH tunneling
}

variable "use_elastic_ip" {
  description = "Assign Elastic IP for stable address"
  type        = bool
  default     = true
}

variable "additional_ssh_keys" {
  description = "Additional SSH public keys to authorize"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
