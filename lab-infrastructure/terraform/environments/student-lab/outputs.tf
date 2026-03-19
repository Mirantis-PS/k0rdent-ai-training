# Outputs for Per-Student Lab Environment

# --- Bastion ---
output "bastion_public_ip" {
  description = "Bastion host public IP"
  value       = module.bastion.public_ip
}

output "bastion_ssh_private_key" {
  description = "Bastion SSH private key"
  value       = module.bastion.ssh_private_key
  sensitive   = true
}

# --- Networking ---
output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = module.networking.nat_gateway_ip
}

# --- k0rdent ---
output "mgmt_node_ids" {
  description = "Instance IDs of management cluster nodes"
  value       = module.k0rdent_mgmt.node_instance_ids
}

output "primary_node_private_ip" {
  description = "Private IP of primary management node"
  value       = module.k0rdent_mgmt.primary_node_ip
}

output "ssh_private_key" {
  description = "SSH private key for k0rdent nodes"
  value       = module.k0rdent_mgmt.ssh_private_key
  sensitive   = true
}

output "connection_info" {
  description = "Connection instructions"
  value       = module.k0rdent_mgmt.connection_info
}

output "ui_access" {
  description = "How to retrieve the k0rdent UI URL"
  value       = module.k0rdent_mgmt.ui_access
}

output "ui_password" {
  description = "k0rdent UI password"
  value       = module.k0rdent_mgmt.ui_password
  sensitive   = true
}

# --- Optional labs ---
output "shared_gpu_private_ip" {
  description = "Shared GPU instance IP"
  value       = var.enable_gpu_lab ? module.gpu_lab[0].shared_gpu_private_ip : null
}

output "metal3_controller_ip" {
  description = "Metal3 controller IP"
  value       = var.enable_metal3 ? module.metal3_dev[0].controller_private_ip : null
}

output "kubevirt_controller_ip" {
  description = "KubeVirt controller IP"
  value       = var.enable_kubevirt ? module.kubevirt_lab[0].controller_private_ip : null
}
