output "node_group_id" {
  description = "ID of the EKS node group"
  value       = aws_eks_node_group.this.id
}

output "node_group_arn" {
  description = "ARN of the EKS node group"
  value       = aws_eks_node_group.this.arn
}

output "node_group_status" {
  description = "Status of the EKS node group"
  value       = aws_eks_node_group.this.status
}

output "node_security_group_id" {
  description = "Security group ID for the worker nodes"
  value       = aws_security_group.nodes.id
}

output "launch_template_id" {
  description = "ID of the launch template for nodes"
  value       = aws_launch_template.nodes.id
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.nodes.latest_version
}
