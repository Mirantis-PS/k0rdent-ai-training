# Outputs for Per-Student IAM Module

output "lab_instance_profile_name" {
  description = "IAM instance profile name for lab instances"
  value       = aws_iam_instance_profile.lab_instance.name
}

output "lab_instance_role_arn" {
  description = "IAM role ARN for lab instances"
  value       = aws_iam_role.lab_instance.arn
}
