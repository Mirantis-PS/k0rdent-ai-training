# Outputs for Bastion Host Module

output "instance_id" {
  description = "Bastion instance ID"
  value       = aws_instance.bastion.id
}

output "public_ip" {
  description = "Bastion public IP address"
  value       = var.use_elastic_ip ? aws_eip.bastion[0].public_ip : aws_instance.bastion.public_ip
}

output "private_ip" {
  description = "Bastion private IP address"
  value       = aws_instance.bastion.private_ip
}

output "ssh_private_key" {
  description = "SSH private key for bastion access"
  value       = tls_private_key.bastion.private_key_pem
  sensitive   = true
}

output "ssh_public_key" {
  description = "SSH public key"
  value       = tls_private_key.bastion.public_key_openssh
}

output "key_pair_name" {
  description = "AWS key pair name"
  value       = aws_key_pair.bastion.key_name
}

output "connection_string" {
  description = "SSH connection string"
  value       = "ssh -i bastion.pem ec2-user@${var.use_elastic_ip ? aws_eip.bastion[0].public_ip : aws_instance.bastion.public_ip}"
}
