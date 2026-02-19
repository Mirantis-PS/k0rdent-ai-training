# Outputs for k0rdent Management Cluster Module

output "node_instance_ids" {
  description = "Instance IDs of management cluster nodes"
  value       = aws_instance.mgmt_node[*].id
}

output "node_private_ips" {
  description = "Private IP addresses of management cluster nodes"
  value       = aws_instance.mgmt_node[*].private_ip
}

output "primary_node_ip" {
  description = "Primary controller node IP address"
  value       = aws_instance.mgmt_node[0].private_ip
}

output "ssh_private_key" {
  description = "SSH private key for accessing instances"
  value       = tls_private_key.mgmt.private_key_openssh
  sensitive   = true
}

output "ssh_public_key" {
  description = "SSH public key"
  value       = tls_private_key.mgmt.public_key_openssh
}

output "key_pair_name" {
  description = "AWS key pair name"
  value       = aws_key_pair.mgmt.key_name
}

output "security_group_id" {
  description = "Security group ID for the management cluster"
  value       = aws_security_group.mgmt_cluster.id
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.mgmt_cluster.name
}

output "engineer_id" {
  description = "Engineer ID for this environment"
  value       = var.engineer_id
}

output "k0sctl_config" {
  description = "Generated k0sctl configuration YAML"
  value       = local.k0sctl_yaml
}

output "k0sctl_config_s3_path" {
  description = "S3 path to k0sctl configuration"
  value       = "s3://${var.artifacts_bucket}/k0sctl/${var.engineer_id}/k0sctl.yaml"
}

output "ssh_key_s3_path" {
  description = "S3 path to SSH private key"
  value       = "s3://${var.artifacts_bucket}/ssh-keys/${var.engineer_id}/mgmt/id_ed25519"
}

output "connection_info" {
  description = "Connection information for the management cluster"
  value = {
    engineer_id     = var.engineer_id
    node_ips        = aws_instance.mgmt_node[*].private_ip
    primary_ip      = aws_instance.mgmt_node[0].private_ip
    ssh_user        = "ubuntu"
    ssh_key_name    = aws_key_pair.mgmt.key_name
    k0s_version     = var.k0s_version
    k0rdent_version = var.k0rdent_version
    flux_version    = var.flux_version
    api_endpoint    = "https://${aws_instance.mgmt_node[0].private_ip}:6443"
  }
}

output "k0s_api_endpoint" {
  description = "k0s API server endpoint"
  value       = "https://${aws_instance.mgmt_node[0].private_ip}:6443"
}

output "cluster_name" {
  description = "k0s cluster name"
  value       = "k0rdent-mgmt-${var.engineer_id}"
}

output "ui_password" {
  description = "k0rdent UI password (generated or provided)"
  value       = local.effective_ui_password
  sensitive   = true
}
