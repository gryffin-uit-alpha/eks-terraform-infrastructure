data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ── [1] VPC ───────────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  cluster_name         = var.cluster_name
  single_nat_gateway   = true # 1 NAT GW dùng chung (production cost saving)
}

# ── [2] Velero S3 (cần ARN trước khi tạo IAM policy) ─────────────────────────
module "velero_infra" {
  source = "./modules/velero-infra"

  project_name   = var.project_name
  environment    = var.environment
  bucket_name    = var.velero_bucket_name
  aws_account_id = local.account_id
  aws_region     = var.aws_region
}

# ── [3] Karpenter SQS (cần ARN trước khi tạo IAM policy) ────────────────────
module "karpenter_infra" {
  source = "./modules/karpenter-infra"

  project_name   = var.project_name
  environment    = var.environment
  cluster_name   = var.cluster_name
  aws_account_id = local.account_id
  aws_region     = var.aws_region
}

# ── [4] IAM (creates cluster role first, then OIDC + IRSA after EKS) ─────────
module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  cluster_name   = var.cluster_name
  aws_account_id = local.account_id

  # OIDC issuer URL from EKS cluster (empty until cluster exists)
  cluster_oidc_issuer_url = try(module.eks.cluster_oidc_issuer_url, "")

  # Velero bucket ARN (để scope policy)
  velero_bucket_arn = module.velero_infra.bucket_arn

  # Karpenter SQS ARN
  karpenter_sqs_queue_arn = module.karpenter_infra.sqs_queue_arn
}

# ── [5] EKS Control Plane (needs VPC + IAM cluster role) ──────────────────────
module "eks" {
  source = "./modules/eks"

  project_name     = var.project_name
  environment      = var.environment
  cluster_name     = var.cluster_name
  cluster_version  = var.cluster_version
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.private_subnet_ids
  cluster_role_arn = module.iam.eks_cluster_role_arn

  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
}

# ── [6] Bastion / Local Registry (cần VPC + IAM) ─────────────────────────────
module "bastion" {
  source = "./modules/bastion"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = var.vpc_cidr
  subnet_id             = module.vpc.private_subnet_ids[0] # AZ đầu tiên
  instance_type         = var.bastion_instance_type
  registry_port         = var.local_registry_port
  instance_profile_name = module.iam.bastion_instance_profile_name
}

# ── [7] Node Group (cần EKS + IAM + Bastion IP) ──────────────────────────────
module "node_group" {
  source = "./modules/node-group"

  project_name  = var.project_name
  environment   = var.environment
  cluster_name  = var.cluster_name
  subnet_ids    = module.vpc.private_subnet_ids
  node_role_arn = module.iam.eks_node_role_arn
  vpc_id        = module.vpc.vpc_id
  vpc_cidr      = var.vpc_cidr

  cluster_security_group_id = module.eks.cluster_security_group_id

  instance_types = var.node_group_instance_types
  desired_size   = var.node_group_desired_size
  min_size       = var.node_group_min_size
  max_size       = var.node_group_max_size
  disk_size_gb   = var.node_group_disk_size_gb

  # CRITICAL: Bastion IP inject vào containerd config
  local_registry_ip   = module.bastion.private_ip
  local_registry_port = var.local_registry_port

  depends_on = [module.eks, module.bastion]
}
