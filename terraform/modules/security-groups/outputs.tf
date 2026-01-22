# Security Groups Module Outputs

output "public_sg_id" {
  description = "ID of the public EC2 security group"
  value       = aws_security_group.public_ec2.id
}

output "private_sg_id" {
  description = "ID of the private EC2 security group"
  value       = aws_security_group.private_ec2.id
}

output "default_sg_id" {
  description = "ID of the default security group for VPC"
  value       = aws_default_security_group.default.id
}