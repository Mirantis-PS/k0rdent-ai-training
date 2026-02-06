# Outputs for KubeVirt Lab Environment Module

output "controller_instance_id" {
  description = "Controller instance ID"
  value       = var.use_spot_instances ? aws_spot_instance_request.controller_spot[0].spot_instance_id : aws_instance.controller.id
}

output "controller_private_ip" {
  description = "Controller private IP address"
  value       = var.use_spot_instances ? aws_spot_instance_request.controller_spot[0].private_ip : aws_instance.controller.private_ip
}

output "controller_public_ip" {
  description = "Controller public IP address (if in public subnet)"
  value       = var.use_spot_instances ? aws_spot_instance_request.controller_spot[0].public_ip : aws_instance.controller.public_ip
}

output "worker_instance_ids" {
  description = "Worker instance IDs"
  value       = var.use_spot_instances ? aws_spot_instance_request.worker_spot[*].spot_instance_id : aws_instance.worker[*].id
}

output "worker_private_ips" {
  description = "Worker private IP addresses"
  value       = var.use_spot_instances ? aws_spot_instance_request.worker_spot[*].private_ip : aws_instance.worker[*].private_ip
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
  value       = aws_cloudwatch_log_group.kubevirt.name
}

output "engineer_id" {
  description = "Engineer ID for this environment"
  value       = var.engineer_id
}

output "connection_info" {
  description = "Connection information for the lab"
  value = {
    controller_ip    = var.use_spot_instances ? aws_spot_instance_request.controller_spot[0].private_ip : aws_instance.controller.private_ip
    worker_ips       = var.use_spot_instances ? aws_spot_instance_request.worker_spot[*].private_ip : aws_instance.worker[*].private_ip
    ssh_user         = "ubuntu"
    ssh_key_name     = aws_key_pair.lab.key_name
    k0s_version      = var.k0s_version
    kubevirt_version = var.kubevirt_version
    cdi_version      = var.cdi_version
  }
}

output "cluster_info" {
  description = "Cluster configuration"
  value = {
    controller_count = 1
    worker_count     = var.worker_count
    total_nodes      = 1 + var.worker_count
  }
}
