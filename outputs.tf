# ── VPC ───────────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "ID của VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs của private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs của public subnets"
  value       = module.vpc.public_subnet_ids
}

# ── EKS ───────────────────────────────────────────────────────────────────────
output "cluster_name" {
  description = "Tên EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint của EKS API server"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN của OIDC provider (dùng cho IRSA)"
  value       = module.iam.oidc_provider_arn
}

# ── Bastion / Registry ────────────────────────────────────────────────────────
output "bastion_private_ip" {
  description = "Private IP của bastion EC2 (địa chỉ local registry)"
  value       = module.bastion.private_ip
}

output "local_registry_endpoint" {
  description = "Endpoint đầy đủ của local registry (dùng trong containerd config)"
  value       = "${module.bastion.private_ip}:${var.local_registry_port}"
}

# ── IAM ───────────────────────────────────────────────────────────────────────
output "karpenter_irsa_role_arn" {
  description = "ARN của IAM Role cho Karpenter (IRSA)"
  value       = module.iam.karpenter_role_arn
}

output "velero_irsa_role_arn" {
  description = "ARN của IAM Role cho Velero (IRSA)"
  value       = module.iam.velero_role_arn
}

output "ebs_csi_driver_role_arn" {
  description = "ARN của IAM Role cho EBS CSI Driver (IRSA)"
  value       = module.iam.ebs_csi_driver_role_arn
}

output "aws_lb_controller_role_arn" {
  description = "ARN của IAM Role cho AWS Load Balancer Controller (IRSA)"
  value       = module.iam.aws_lb_controller_role_arn
}

# ── Velero S3 ─────────────────────────────────────────────────────────────────
output "velero_bucket_name" {
  description = "Tên S3 bucket Velero backup"
  value       = module.velero_infra.bucket_name
}

# ── Karpenter ─────────────────────────────────────────────────────────────────
output "karpenter_sqs_queue_url" {
  description = "URL của SQS queue cho Karpenter interruption handling"
  value       = module.karpenter_infra.sqs_queue_url
}

output "karpenter_sqs_queue_arn" {
  description = "ARN của SQS queue cho Karpenter"
  value       = module.karpenter_infra.sqs_queue_arn
}

# ── Storage Classes ───────────────────────────────────────────────────────────
output "default_storage_class" {
  description = "Tên của default StorageClass (gp3)"
  value       = module.storage_classes.default_storage_class
}

output "storage_classes" {
  description = "Danh sách tất cả StorageClasses được tạo"
  value       = module.storage_classes.storage_classes
}
