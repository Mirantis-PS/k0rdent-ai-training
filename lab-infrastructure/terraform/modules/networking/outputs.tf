# Outputs for Per-Student Networking Module

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "gpu_subnet_id" {
  description = "GPU subnet ID"
  value       = aws_subnet.gpu.id
}

output "bastion_security_group_id" {
  description = "Bastion security group ID"
  value       = aws_security_group.bastion.id
}

output "lab_instance_security_group_id" {
  description = "Lab instance security group ID"
  value       = aws_security_group.lab_instance.id
}

output "k8s_cluster_security_group_id" {
  description = "K8s cluster security group ID"
  value       = aws_security_group.k8s_cluster.id
}

output "gpu_lab_security_group_id" {
  description = "GPU lab security group ID"
  value       = aws_security_group.gpu_lab.id
}

output "availability_zones" {
  description = "Availability zones in use"
  value       = local.azs
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = aws_eip.nat.public_ip
}
