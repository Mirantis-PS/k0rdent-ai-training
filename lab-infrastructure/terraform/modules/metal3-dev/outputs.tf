# Outputs for Metal3 Development Environment Module

output "controller_instance_id" {
  description = "Controller instance ID"
  value       = var.use_spot_instances ? aws_spot_instance_request.controller_spot[0].spot_instance_id : aws_instance.controller[0].id
}

output "controller_private_ip" {
  description = "Controller private IP address"
  value       = var.use_spot_instances ? aws_spot_instance_request.controller_spot[0].private_ip : aws_instance.controller[0].private_ip
}

output "controller_public_ip" {
  description = "Controller public IP address (if in public subnet)"
  value       = var.use_spot_instances ? aws_spot_instance_request.controller_spot[0].public_ip : aws_instance.controller[0].public_ip
}

output "worker_host_instance_ids" {
  description = "Worker host instance IDs"
  value       = aws_instance.worker_host[*].id
}

output "worker_host_private_ips" {
  description = "Worker host private IP addresses"
  value       = aws_instance.worker_host[*].private_ip
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
  value       = aws_cloudwatch_log_group.metal3.name
}

output "engineer_id" {
  description = "Engineer ID for this environment"
  value       = var.engineer_id
}

output "connection_info" {
  description = "Connection information for the lab"
  value = {
    controller_ip  = var.use_spot_instances ? aws_spot_instance_request.controller_spot[0].private_ip : aws_instance.controller[0].private_ip
    ssh_user       = "ubuntu"
    ssh_key_name   = aws_key_pair.lab.key_name
    k0s_version    = var.k0s_version
    metal3_version = var.metal3_version
  }
}
