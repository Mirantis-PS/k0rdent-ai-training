# Outputs for GPU Lab Environment Module

output "shared_gpu_instance_id" {
  description = "Shared GPU instance ID"
  value       = var.enable_shared_gpu ? (var.use_spot_instances ? aws_spot_instance_request.gpu_shared_spot[0].spot_instance_id : aws_instance.gpu_shared[0].id) : null
}

output "shared_gpu_private_ip" {
  description = "Shared GPU instance private IP"
  value       = var.enable_shared_gpu ? (var.use_spot_instances ? aws_spot_instance_request.gpu_shared_spot[0].private_ip : aws_instance.gpu_shared[0].private_ip) : null
}

output "shared_gpu_public_ip" {
  description = "Shared GPU instance public IP (if in public subnet)"
  value       = var.enable_shared_gpu ? (var.use_spot_instances ? aws_spot_instance_request.gpu_shared_spot[0].public_ip : aws_instance.gpu_shared[0].public_ip) : null
}

output "advanced_gpu_instance_id" {
  description = "Advanced GPU instance ID (8x A100)"
  value       = var.enable_advanced_gpu ? aws_instance.gpu_advanced[0].id : null
}

output "advanced_gpu_private_ip" {
  description = "Advanced GPU instance private IP"
  value       = var.enable_advanced_gpu ? aws_instance.gpu_advanced[0].private_ip : null
}

output "ssh_private_key" {
  description = "SSH private key for accessing instances"
  value       = tls_private_key.lab.private_key_pem
  sensitive   = true
}

output "ssh_public_key" {
  description = "SSH public key"
  value       = tls_private_key.lab.public_key_openssh
}

output "key_pair_name" {
  description = "AWS key pair name"
  value       = aws_key_pair.lab.key_name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.gpu.name
}

output "lab_session_id" {
  description = "Lab session ID"
  value       = var.lab_session_id
}

output "placement_group_id" {
  description = "Placement group ID for GPU instances"
  value       = aws_placement_group.gpu.id
}

output "gpu_info" {
  description = "GPU instance information"
  value = {
    shared_enabled   = var.enable_shared_gpu
    advanced_enabled = var.enable_advanced_gpu
    shared_type      = var.shared_gpu_instance_type
    advanced_type    = var.advanced_gpu_instance_type
    spot_enabled     = var.use_spot_instances
  }
}

output "connection_info" {
  description = "Connection information for the GPU lab"
  value = {
    shared_ip      = var.enable_shared_gpu ? (var.use_spot_instances ? aws_spot_instance_request.gpu_shared_spot[0].private_ip : aws_instance.gpu_shared[0].private_ip) : null
    advanced_ip    = var.enable_advanced_gpu ? aws_instance.gpu_advanced[0].private_ip : null
    ssh_user       = "ubuntu"
    ssh_key_name   = aws_key_pair.lab.key_name
    engineer_slots = var.engineer_slots
    k0s_version    = var.k0s_version
    gpu_operator   = var.gpu_operator_version
  }
}
