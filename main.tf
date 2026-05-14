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
  single_nat_gateway   = false # ✅ FIXED: 3 NAT GWs (1 per AZ) for HA
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

# ── [4] EKS Control Plane (cần VPC trước) ────────────────────────────────────
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


# ── [5] IAM (cần OIDC từ EKS, bucket ARN từ Velero, SQS ARN từ Karpenter) ───
# Lưu ý: IAM role cho EKS cluster cần tồn tại TRƯỚC KHI tạo EKS cluster.
# Terraform giải quyết vòng tròn này bằng cách tạo EKS cluster role trong IAM
# module trước (cluster_role_arn), rồi OIDC được lấy SAU KHI EKS up.
module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  cluster_name   = var.cluster_name
  aws_account_id = local.account_id

  # OIDC — lấy từ EKS module (tạo sau khi cluster up)
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url

  # Velero bucket ARN (để scope policy)
  velero_bucket_arn = module.velero_infra.bucket_arn

  # Karpenter SQS ARN
  karpenter_sqs_queue_arn = module.karpenter_infra.sqs_queue_arn
}

# ── [6] Bastion / Local Registry (cần VPC + IAM) ─────────────────────────────
module "bastion" {
  source = "./modules/bastion"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = var.vpc_cidr
  subnet_id             = module.vpc.public_subnet_ids[0] # Move to Public Subnet for temporary access
  instance_type         = var.bastion_instance_type
  registry_port         = var.local_registry_port
  instance_profile_name = module.iam.bastion_instance_profile_name
}

# ══════════════════════════════════════════════════════════════════════════════
# ── [7] BASELINE NODE GROUP - COST-OPTIMIZED SINGLE NODE GROUP ───────────────
# ══════════════════════════════════════════════════════════════════════════════
# Replaces 3 fragmented node groups (system, monitoring, app) with a single
# baseline node group that runs ALL critical infrastructure workloads.
#
# COST SAVINGS: 6 nodes → 2 nodes = ~$216/month savings (~$2,600/year)
# - Old: 6 nodes × m7i-flex.large/c7i-flex.large = ~$432/month
# - New: 2 nodes × m7i-flex.large = ~$138/month
# ══════════════════════════════════════════════════════════════════════════════

module "node_group_baseline" {
  source = "./modules/node-group"

  node_group_name              = "baseline"
  create_worker_security_group = true

  project_name  = var.project_name
  environment   = var.environment
  cluster_name  = var.cluster_name
  subnet_ids    = module.vpc.private_subnet_ids
  node_role_arn = module.iam.eks_node_role_arn
  vpc_id        = module.vpc.vpc_id
  vpc_cidr      = var.vpc_cidr

  cluster_security_group_id = module.eks.cluster_security_group_id

  # ✅ OPTIMIZED INSTANCES: 2 vCPU, 8GB RAM per node (using variable)
  instance_types = var.node_group_instance_types

  # ✅ ADJUSTED FOR QUOTA: 3 nodes (6 vCPU) + 1 Bastion (2 vCPU) = 8 vCPU limit
  desired_size = 3
  min_size     = 3
  max_size     = 4 # Limit max to avoid quota errors

  disk_size_gb = 50

  # ✅ NO TAINTS: Accept all workloads
  # Allows infrastructure + observability + apps to schedule freely
  # Karpenter will handle burst workloads
  taints = []

  labels = {
    role     = "baseline"
    workload = "infrastructure"
  }

  local_registry_ip   = module.bastion.private_ip
  local_registry_port = var.local_registry_port

  depends_on = [module.eks, module.bastion]
}

# ══════════════════════════════════════════════════════════════════════════════
# ── [8] Core EKS Add-ons (NO TOLERATIONS NEEDED - baseline has no taints) ────
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # ✅ NO TOLERATIONS: Baseline nodes have no taints
  configuration_values = jsonencode({
    tolerations  = []
    replicaCount = 2
    resources = {
      requests = {
        cpu    = "100m"
        memory = "128Mi"
      }
      limits = {
        cpu    = "200m"
        memory = "256Mi"
      }
    }
  })

  depends_on = [module.node_group_baseline]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [module.node_group_baseline]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [module.node_group_baseline]
}

# ── [9] Storage Classes (default gp3 for EBS CSI Driver) ──────────────────────
module "storage_classes" {
  source = "./modules/storage-classes"

  cluster_name = var.cluster_name

  depends_on = [
    aws_eks_addon.vpc_cni,
    module.node_group_baseline
  ]
}
