output "instance_id" {
  description = "ID of the bastion EC2 instance"
  value       = aws_instance.bastion.id
}

output "private_ip" {
  description = "Private IP address of the bastion instance"
  value       = aws_instance.bastion.private_ip
}

output "security_group_id" {
  description = "Security group ID of the bastion instance"
  value       = aws_security_group.bastion.id
}
