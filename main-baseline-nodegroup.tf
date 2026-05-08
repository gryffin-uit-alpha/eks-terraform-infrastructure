# ══════════════════════════════════════════════════════════════════════════════
# BASELINE NODE GROUP - CONSOLIDATED INFRASTRUCTURE NODES
# ══════════════════════════════════════════════════════════════════════════════
# This replaces the 3 fragmented node groups (system, monitoring, app) with a
# single baseline node group that runs ALL critical infrastructure workloads.
#
# MIGRATION PLAN:
# 1. Apply this file to create the baseline node group
# 2. Wait for 2 nodes to be Ready
# 3. Comment out the old node groups in main.tf
# 4. Kubectl drain old nodes
# 5. Terraform apply to delete old node groups
#
# COST SAVINGS: 6 nodes → 2 nodes = ~$300/month savings
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

  # ✅ LARGER INSTANCES: 4 vCPU, 16GB RAM per node
  # Rationale: Consolidated workloads need more resources than fragmented setup
  # Total capacity: 2 nodes × 4 vCPU = 8 vCPU baseline
  instance_types = ["m7i-flex.xlarge"]

  # ✅ MINIMAL BASELINE: Only 2 nodes (vs 6 nodes before)
  desired_size = 2
  min_size     = 2
  max_size     = 4  # Can scale up if needed

  disk_size_gb = 50

  # ✅ NO TAINTS: Accept all workloads
  # This allows infrastructure + observability + apps to schedule freely
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
# COREDNS CONFIGURATION - NO TOLERATIONS NEEDED
# ══════════════════════════════════════════════════════════════════════════════
# Since baseline nodes have NO taints, CoreDNS can schedule without tolerations
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_eks_addon" "coredns_baseline" {
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

resource "aws_eks_addon" "kube_proxy_baseline" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [module.node_group_baseline]
}

resource "aws_eks_addon" "vpc_cni_baseline" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [module.node_group_baseline]
}

# ══════════════════════════════════════════════════════════════════════════════
# MIGRATION INSTRUCTIONS
# ══════════════════════════════════════════════════════════════════════════════
#
# STEP 1: Create baseline node group
#   cd eks-terraform-infrastructure
#   terraform apply -target=module.node_group_baseline
#
#   Wait for nodes to be Ready:
#   kubectl get nodes -l role=baseline
#
# STEP 2: Remove old CoreDNS addon (to avoid conflict)
#   kubectl delete deployment coredns -n kube-system --ignore-not-found
#   terraform apply -target=aws_eks_addon.coredns_baseline
#
# STEP 3: Taint old nodes to prevent new pods
#   kubectl taint nodes -l role=system role=deprecated:NoSchedule
#   kubectl taint nodes -l role=monitoring role=deprecated:NoSchedule
#   kubectl taint nodes -l role=application role=deprecated:NoSchedule
#
# STEP 4: Drain old nodes (forces pod migration)
#   kubectl drain -l role=system --ignore-daemonsets --delete-emptydir-data
#   kubectl drain -l role=monitoring --ignore-daemonsets --delete-emptydir-data
#   kubectl drain -l role=application --ignore-daemonsets --delete-emptydir-data
#
# STEP 5: Verify all pods running on baseline nodes
#   kubectl get pods -A -o wide | grep -v baseline | grep -v Completed
#   # Should only show DaemonSets on old nodes
#
# STEP 6: Comment out old node groups in main.tf:
#   # module "node_group_system" { ... }
#   # module "node_group_monitoring" { ... }
#   # module "node_group_app" { ... }
#   # resource "aws_eks_addon" "coredns" { ... }
#   # resource "aws_eks_addon" "kube_proxy" { ... }
#   # resource "aws_eks_addon" "vpc_cni" { ... }
#
# STEP 7: Delete old node groups
#   terraform apply
#
# STEP 8: Verify cost savings
#   # Old: 6 nodes × $0.10/hour = $432/month
#   # New: 2 nodes × $0.15/hour = $216/month
#   # Savings: $216/month = $2,592/year
#
# ══════════════════════════════════════════════════════════════════════════════
