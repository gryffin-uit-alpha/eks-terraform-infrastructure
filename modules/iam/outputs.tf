output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node IAM role"
  value       = aws_iam_role.eks_node.arn
}

output "eks_node_instance_profile_name" {
  description = "Name of the EKS node instance profile"
  value       = aws_iam_instance_profile.eks_node.name
}

output "karpenter_role_arn" {
  description = "ARN of the Karpenter IRSA role"
  value       = length(aws_iam_role.karpenter) > 0 ? aws_iam_role.karpenter[0].arn : ""
}

output "velero_role_arn" {
  description = "ARN of the Velero IRSA role"
  value       = length(aws_iam_role.velero) > 0 ? aws_iam_role.velero[0].arn : ""
}

output "bastion_instance_profile_name" {
  description = "Name of the bastion instance profile"
  value       = aws_iam_instance_profile.bastion.name
}

output "bastion_role_arn" {
  description = "ARN of the bastion IAM role"
  value       = aws_iam_role.bastion.arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = local.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC Provider for EKS (without https://)"
  value       = local.oidc_provider_url
}
