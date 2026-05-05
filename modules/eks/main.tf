locals {
  name = "${var.project_name}-${var.environment}"
}

# ── Security Group cho EKS Control Plane ──────────────────────────────────────
resource "aws_security_group" "cluster" {
  name        = "${local.name}-eks-cluster-sg"
  description = "Security group cho EKS control plane"
  vpc_id      = var.vpc_id

  # Cho phép all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = { Name = "${local.name}-eks-cluster-sg" }
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.endpoint_public_access_cidrs : null
  }

  # Bật đầy đủ cluster logging
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Bật EKS add-on cho CoreDNS, kube-proxy, vpc-cni
  # (sẽ dùng aws_eks_addon resource riêng)

  tags = { Name = var.cluster_name }
}

