# Terraform Refactor Plan - Multi-Node Group Architecture

**Date:** 2026-05-07  
**Objective:** Transform single node group to dedicated node groups (system, monitoring, app)  
**Strategy:** Zero-downtime migration with rollback capability

---

## Overview

**Current Structure:**
```
eks-terraform-infrastructure/
├── main.tf                     # Calls single node_group module
├── modules/
│   └── node-group/            # Single node group module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
```

**Proposed Structure:**
```
eks-terraform-infrastructure/
├── main.tf                     # Calls THREE node group modules
├── modules/
│   ├── node-group-base/       # Shared base module (DRY)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── system-ng/             # System workloads (ArgoCD, Traefik, etc.)
│   ├── monitoring-ng/         # Monitoring stack (Prometheus, Grafana)
│   └── app-ng/                # Application workloads
```

---

## Refactor Strategy

### Option A: Refactor Existing Module (Recommended)
**Keep** `modules/node-group/` as a **reusable base module** with parameters for:
- Node group name
- Instance types
- Taints
- Labels
- Scaling config

**Call it three times** from `main.tf` with different configurations.

**Pros:**
- ✅ DRY principle - single source of truth
- ✅ Easier to maintain
- ✅ Consistent security group rules across all node groups
- ✅ Less code duplication

**Cons:**
- ⚠️ Requires careful variable design

### Option B: Duplicate Module Three Times
Create separate `system-ng/`, `monitoring-ng/`, `app-ng/` modules.

**Pros:**
- ✅ Complete isolation
- ✅ Can customize per workload type

**Cons:**
- ❌ Code duplication
- ❌ Security group drift risk
- ❌ Harder to maintain

**Decision:** **Use Option A** - Reusable base module

---

## Implementation Plan

### Step 1: Refactor `modules/node-group/` to Accept Parameters

**Current:** Hardcoded single node group  
**Target:** Parameterized reusable module

**Changes Required:**

#### `modules/node-group/variables.tf`
```hcl
# NEW: Node group identity
variable "node_group_name" {
  description = "Unique name for this node group (system-ng, monitoring-ng, app-ng)"
  type        = string
}

# NEW: Taints for workload isolation
variable "taints" {
  description = "List of taints to apply to nodes in this group"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

# NEW: Labels for node identification
variable "labels" {
  description = "Map of labels to apply to nodes"
  type        = map(string)
  default     = {}
}

# EXISTING (keep these)
variable "instance_types" { ... }
variable "desired_size" { ... }
variable "min_size" { ... }
variable "max_size" { ... }
variable "disk_size_gb" { ... }
variable "local_registry_ip" { ... }
variable "local_registry_port" { ... }
variable "cluster_name" { ... }
variable "subnet_ids" { ... }
variable "node_role_arn" { ... }
variable "vpc_id" { ... }
variable "vpc_cidr" { ... }
variable "cluster_security_group_id" { ... }
```

#### `modules/node-group/main.tf`
```hcl
locals {
  name             = "${var.project_name}-${var.environment}-${var.node_group_name}"
  # ... existing locals ...
}

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = local.name  # Changed from hardcoded
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.instance_types

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  # NEW: Dynamic taints
  dynamic "taint" {
    for_each = var.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  # NEW: Merge default + custom labels
  labels = merge(
    {
      environment = var.environment
    },
    var.labels
  )

  # ... rest unchanged ...
}
```

---

### Step 2: Update Root `main.tf`

#### Current (Single Node Group):
```hcl
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

  local_registry_ip   = module.bastion.private_ip
  local_registry_port = var.local_registry_port

  depends_on = [module.eks, module.bastion]
}
```

#### Proposed (Three Node Groups):
```hcl
# ── [7a] System Node Group ────────────────────────────────────────────
module "node_group_system" {
  source = "./modules/node-group"

  node_group_name = "system-ng"

  project_name  = var.project_name
  environment   = var.environment
  cluster_name  = var.cluster_name
  subnet_ids    = module.vpc.private_subnet_ids
  node_role_arn = module.iam.eks_node_role_arn
  vpc_id        = module.vpc.vpc_id
  vpc_cidr      = var.vpc_cidr

  cluster_security_group_id = module.eks.cluster_security_group_id

  instance_types = ["m7i-flex.large"]
  desired_size   = 2
  min_size       = 2
  max_size       = 4
  disk_size_gb   = 50

  taints = [{
    key    = "role"
    value  = "system"
    effect = "NO_SCHEDULE"
  }]

  labels = {
    role     = "system"
    workload = "infrastructure"
  }

  local_registry_ip   = module.bastion.private_ip
  local_registry_port = var.local_registry_port

  depends_on = [module.eks, module.bastion]
}

# ── [7b] Monitoring Node Group ────────────────────────────────────────
module "node_group_monitoring" {
  source = "./modules/node-group"

  node_group_name = "monitoring-ng"

  project_name  = var.project_name
  environment   = var.environment
  cluster_name  = var.cluster_name
  subnet_ids    = module.vpc.private_subnet_ids
  node_role_arn = module.iam.eks_node_role_arn
  vpc_id        = module.vpc.vpc_id
  vpc_cidr      = var.vpc_cidr

  cluster_security_group_id = module.eks.cluster_security_group_id

  instance_types = ["m7i-flex.large"]
  desired_size   = 2
  min_size       = 2
  max_size       = 4
  disk_size_gb   = 50

  taints = [{
    key    = "role"
    value  = "monitoring"
    effect = "NO_SCHEDULE"
  }]

  labels = {
    role     = "monitoring"
    workload = "observability"
  }

  local_registry_ip   = module.bastion.private_ip
  local_registry_port = var.local_registry_port

  depends_on = [module.eks, module.bastion]
}

# ── [7c] Application Node Group ───────────────────────────────────────
module "node_group_app" {
  source = "./modules/node-group"

  node_group_name = "app-ng"

  project_name  = var.project_name
  environment   = var.environment
  cluster_name  = var.cluster_name
  subnet_ids    = module.vpc.private_subnet_ids
  node_role_arn = module.iam.eks_node_role_arn
  vpc_id        = module.vpc.vpc_id
  vpc_cidr      = var.vpc_cidr

  cluster_security_group_id = module.eks.cluster_security_group_id

  instance_types = ["c7i-flex.large"]
  desired_size   = 2
  min_size       = 2
  max_size       = 10
  disk_size_gb   = 50

  taints = [{
    key    = "role"
    value  = "app"
    effect = "NO_SCHEDULE"
  }]

  labels = {
    role     = "application"
    workload = "app"
  }

  local_registry_ip   = module.bastion.private_ip
  local_registry_port = var.local_registry_port

  depends_on = [module.eks, module.bastion]
}
```

---

### Step 3: Update CoreDNS Toleration

**Current:** Tolerates `node-group=managed:NoSchedule`

**Proposed:** Tolerate `role=system:NoSchedule`

#### `main.tf` (CoreDNS addon block):
```hcl
resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # CoreDNS must schedule on system-ng
  configuration_values = jsonencode({
    tolerations = [
      {
        key      = "role"
        value    = "system"
        effect   = "NoSchedule"
        operator = "Equal"
      }
    ]
    # Ensure 2 replicas for HA
    replicaCount = 2
    # Anti-affinity to spread across AZs
    affinity = {
      podAntiAffinity = {
        preferredDuringSchedulingIgnoredDuringExecution = [
          {
            weight = 100
            podAffinityTerm = {
              labelSelector = {
                matchLabels = {
                  "k8s-app" = "kube-dns"
                }
              }
              topologyKey = "topology.kubernetes.io/zone"
            }
          }
        ]
      }
    }
  })

  depends_on = [module.node_group_system]
}
```

---

### Step 4: Update ArgoCD Application Tolerations

#### `Pattern-App-of-Apps/apps/wave-1-traefik.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: traefik
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  # ... existing config ...
  source:
    helm:
      values: |
        # NEW: Add toleration for system-ng
        tolerations:
          - key: role
            operator: Equal
            value: system
            effect: NoSchedule

        # NEW: Add node selector
        nodeSelector:
          role: system

        # EXISTING: Keep all existing config
        deployment:
          replicas: 2
        service:
          type: LoadBalancer
          annotations:
            service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
        # ... rest of config ...
```

#### `Pattern-App-of-Apps/apps/wave-3-prometheus-stack.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-stack
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  source:
    helm:
      values: |
        # Global tolerations for all components
        defaultTolerations:
          - key: role
            operator: Equal
            value: monitoring
            effect: NoSchedule

        # Node selector for all components
        defaultNodeSelector:
          role: monitoring

        prometheus:
          prometheusSpec:
            # Override with specific tolerations
            tolerations:
              - key: role
                operator: Equal
                value: monitoring
                effect: NoSchedule
            nodeSelector:
              role: monitoring
            # ... existing config ...

        grafana:
          tolerations:
            - key: role
              operator: Equal
              value: monitoring
              effect: NoSchedule
          nodeSelector:
            role: monitoring
          # ... existing config ...

        alertmanager:
          alertmanagerSpec:
            tolerations:
              - key: role
                operator: Equal
                value: monitoring
                effect: NoSchedule
            nodeSelector:
              role: monitoring
```

#### `Pattern-App-of-Apps/wave-1/karpenter/values.yaml`
```yaml
karpenter:
  settings:
    clusterName: "eks-production"
    interruptionQueue: "eks-cluster-production-karpenter-interruption"

  serviceAccount:
    name: karpenter
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::991216470347:role/eks-cluster-production-karpenter-irsa"

  # NEW: Karpenter controller runs on system-ng
  tolerations:
    - key: role
      operator: Equal
      value: system
      effect: NoSchedule

  nodeSelector:
    role: system

  controller:
    resources:
      requests:
        cpu: "250m"
        memory: "512Mi"
      limits:
        cpu: "1"
        memory: "1Gi"

  replicas: 2

  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: karpenter
          topologyKey: topology.kubernetes.io/zone
```

---

### Step 5: Verify DaemonSet Tolerations

**Check:** Ensure critical DaemonSets tolerate ALL taints

#### AWS VPC CNI
```bash
kubectl get daemonset aws-node -n kube-system -o yaml | grep -A 10 tolerations
```

**Expected:**
```yaml
tolerations:
  - operator: Exists  # Tolerates ALL taints including custom ones
```

If missing, patch:
```bash
kubectl patch daemonset aws-node -n kube-system -p '
spec:
  template:
    spec:
      tolerations:
        - operator: Exists
'
```

#### kube-proxy
```bash
kubectl get daemonset kube-proxy -n kube-system -o yaml | grep -A 10 tolerations
```

**Expected:**
```yaml
tolerations:
  - operator: Exists
```

#### node-exporter (from Prometheus stack)
Should inherit from `nodeExporter.tolerations` in Helm values:
```yaml
nodeExporter:
  enabled: true
  tolerations:
    - operator: Exists  # Run on all nodes
```

---

## Migration Steps (Zero Downtime)

### Phase 1: Add New Node Groups (Keep Old)
```bash
cd eks-terraform-infrastructure

# 1. Pull latest code with node group refactor
git pull origin main

# 2. Review changes
terraform plan

# Expected output:
# + module.node_group_system.aws_eks_node_group.this
# + module.node_group_system.aws_launch_template.nodes
# + module.node_group_system.aws_security_group.nodes
# + module.node_group_monitoring.aws_eks_node_group.this
# + module.node_group_monitoring.aws_launch_template.nodes
# + module.node_group_monitoring.aws_security_group.nodes
# + module.node_group_app.aws_eks_node_group.this
# + module.node_group_app.aws_launch_template.nodes
# + module.node_group_app.aws_security_group.nodes
# ~ module.eks.aws_eks_addon.coredns (toleration updated)

# OLD node group remains (no destroy)

# 3. Apply
terraform apply

# 4. Wait for nodes to be ready
kubectl get nodes -w
# Expected: 8 nodes total (2 old + 6 new)

# 5. Label new nodes for verification
kubectl get nodes --show-labels | grep role=system
kubectl get nodes --show-labels | grep role=monitoring
kubectl get nodes --show-labels | grep role=application
```

**Checkpoint:** All 8 nodes ready and healthy

---

### Phase 2: Update Workload Tolerations

```bash
cd Pattern-App-of-Apps

# 1. Update ArgoCD Application manifests
# (Files already updated in Step 4 above)

# 2. Commit and push
git add apps/
git commit -m "feat: add node group tolerations for dedicated node groups"
git push

# 3. Wait for ArgoCD to sync
kubectl get applications -n argocd -w

# 4. Verify pods migrate to new nodes
watch kubectl get pods -A -o wide

# Expected:
# - Traefik pods on system-ng nodes
# - Prometheus pods on monitoring-ng nodes
# - Application pods pending (need app-ng tolerations)
```

**Checkpoint:** System and monitoring workloads on correct node groups

---

### Phase 3: Migrate Applications to app-ng

```bash
# 1. Add tolerations to your application Helm charts or manifests
# Example for a backend deployment:

apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  template:
    spec:
      tolerations:
        - key: role
          operator: Equal
          value: app
          effect: NoSchedule
      nodeSelector:
        role: application
      # ... rest of spec ...

# 2. Apply changes via ArgoCD or kubectl

# 3. Verify pods schedule on app-ng
kubectl get pods -n <your-app-namespace> -o wide
```

**Checkpoint:** All application pods on app-ng nodes

---

### Phase 4: Decommission Old Node Group

```bash
# 1. Verify no pods remain on old nodes
kubectl get pods -A -o wide | grep ip-10-0-11-97  # Old node 1
kubectl get pods -A -o wide | grep ip-10-0-13-69  # Old node 2

# Expected: Only DaemonSets (aws-node, kube-proxy, node-exporter)

# 2. Cordon old nodes
kubectl cordon ip-10-0-11-97.ec2.internal
kubectl cordon ip-10-0-13-69.ec2.internal

# 3. Drain old nodes
kubectl drain ip-10-0-11-97.ec2.internal --ignore-daemonsets --delete-emptydir-data
kubectl drain ip-10-0-13-69.ec2.internal --ignore-daemonsets --delete-emptydir-data

# 4. Remove old node group from Terraform
# Comment out or delete old node_group module call in main.tf

# 5. Apply Terraform
terraform plan
# Expected: - module.node_group.aws_eks_node_group.this (destroy)

terraform apply

# 6. Verify cluster health
kubectl get nodes
# Expected: 6 nodes (system-ng: 2, monitoring-ng: 2, app-ng: 2)

kubectl get pods -A
# Expected: All pods Running
```

**Checkpoint:** Migration complete, old node group destroyed

---

## Rollback Plan

### If Issues in Phase 1 (New nodes won't join)
```bash
# Destroy new node groups
terraform destroy -target=module.node_group_system
terraform destroy -target=module.node_group_monitoring
terraform destroy -target=module.node_group_app

# Old node group remains functional
```

### If Issues in Phase 2-3 (Workloads won't schedule)
```bash
# Remove taints from new node groups temporarily
kubectl taint nodes -l role=system role=system:NoSchedule-
kubectl taint nodes -l role=monitoring role=monitoring:NoSchedule-
kubectl taint nodes -l role=app role=app:NoSchedule-

# Pods will now schedule on any node
# Investigate toleration issues
```

### If Critical Failure
```bash
# Revert Git commits
git revert HEAD~3..HEAD
git push

# ArgoCD will roll back workload changes

# Destroy new node groups via Terraform
terraform destroy -target=module.node_group_system
terraform destroy -target=module.node_group_monitoring
terraform destroy -target=module.node_group_app

# Cluster returns to pre-migration state
```

---

## Testing Checklist

### After Phase 1 (Nodes Created)
- [ ] 6 new nodes join cluster
- [ ] New nodes have correct labels (`role=system`, etc.)
- [ ] New nodes have correct taints
- [ ] New nodes healthy in AWS console
- [ ] DaemonSets running on all 8 nodes (old + new)

### After Phase 2 (System/Monitoring Migrated)
- [ ] Traefik pods on system-ng nodes
- [ ] ArgoCD pods on system-ng nodes
- [ ] Prometheus pods on monitoring-ng nodes
- [ ] Grafana pods on monitoring-ng nodes
- [ ] CoreDNS pods on system-ng nodes
- [ ] DNS resolution working cluster-wide
- [ ] Metrics collection working

### After Phase 3 (Applications Migrated)
- [ ] Application pods on app-ng nodes
- [ ] Ingress routing to applications working
- [ ] Prometheus scraping application metrics
- [ ] Cross-node-group communication verified

### After Phase 4 (Old Nodes Removed)
- [ ] Only 6 nodes in cluster
- [ ] All pods Running
- [ ] No pod scheduling issues
- [ ] ArgoCD sync working
- [ ] Monitoring dashboards working
- [ ] Application endpoints responding

---

## Estimated Timeline

| Phase | Duration | Risk |
|-------|----------|------|
| Phase 1: Add new nodes | 30 min | 🟢 Low |
| Phase 2: Migrate system/monitoring | 1 hour | 🟡 Medium |
| Phase 3: Migrate applications | 1 hour | 🟡 Medium |
| Phase 4: Remove old nodes | 30 min | 🟢 Low |
| **Total** | **3-4 hours** | 🟡 Medium |

**Recommendation:** Execute during maintenance window or low-traffic period.

---

## Security Group Considerations

**Important:** All node groups should use the **same security group rules** for pod networking.

**Current:** Single security group `eks-cluster-production-nodes-sg`

**Proposed:** Each node group gets its own SG but with **identical rules**:

```hcl
# modules/node-group/main.tf

resource "aws_security_group" "nodes" {
  name        = "${local.name}-nodes-sg"
  description = "Security group for ${var.node_group_name} EKS worker nodes"
  vpc_id      = var.vpc_id

  # Node-to-node (self-referencing - same SG)
  ingress {
    description = "Node to node all ports"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # CRITICAL: Cross-node-group pod communication (VPC CIDR)
  ingress {
    description = "Pod to pod across ALL node groups (VPC CIDR)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]  # 10.0.0.0/16 covers all node groups
  }

  # CRITICAL: Service CIDR (already fixed)
  ingress {
    description = "Kubernetes Service CIDR - pod-to-service TCP"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["172.20.0.0/16"]
  }

  # Control plane to nodes
  ingress {
    description     = "Control plane to nodes"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [var.cluster_security_group_id]
  }

  # Kubelet API
  ingress {
    description     = "Kubelet API"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [var.cluster_security_group_id]
  }

  # Egress rules (same for all node groups)
  egress {
    description = "HTTPS to AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "SSH for Git"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Pull from local registry"
    from_port   = var.local_registry_port
    to_port     = var.local_registry_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Kubernetes Service CIDR - return traffic"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["172.20.0.0/16"]
  }

  tags = { Name = "${local.name}-nodes-sg" }
}
```

**Why separate SGs per node group:**
- Easier to debug (identify which node group has issues)
- Allows future per-node-group rules if needed
- Maintains blast radius isolation

**Why identical rules:**
- Pods must communicate across node groups
- Services route traffic across all nodes
- Monitoring scrapes all targets

---

## Variables to Add

### `variables.tf` (root)
```hcl
# NEW: Node group configurations can be exposed as variables
# Or hardcode in main.tf for simplicity (recommended)

# If using variables:
variable "system_ng_instance_types" {
  description = "Instance types for system node group"
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "system_ng_min_size" {
  type    = number
  default = 2
}

variable "system_ng_max_size" {
  type    = number
  default = 4
}

# Repeat for monitoring_ng and app_ng...
```

**Recommendation:** Hardcode in `main.tf` instead of exposing as root variables. Reduces complexity.

---

## Outputs to Add

### `outputs.tf` (root)
```hcl
# System Node Group
output "system_ng_nodes" {
  description = "System node group details"
  value = {
    node_group_id  = module.node_group_system.node_group_id
    node_group_arn = module.node_group_system.node_group_arn
    security_group_id = module.node_group_system.security_group_id
  }
}

# Monitoring Node Group
output "monitoring_ng_nodes" {
  description = "Monitoring node group details"
  value = {
    node_group_id  = module.node_group_monitoring.node_group_id
    node_group_arn = module.node_group_monitoring.node_group_arn
    security_group_id = module.node_group_monitoring.security_group_id
  }
}

# Application Node Group
output "app_ng_nodes" {
  description = "Application node group details"
  value = {
    node_group_id  = module.node_group_app.node_group_id
    node_group_arn = module.node_group_app.node_group_arn
    security_group_id = module.node_group_app.security_group_id
  }
}
```

---

## Summary

**Total Changes Required:**

| File | Change Type | Lines Changed |
|------|-------------|---------------|
| `modules/node-group/variables.tf` | Add parameters | +30 |
| `modules/node-group/main.tf` | Add dynamic blocks | +20 |
| `main.tf` | Add 3 node group calls | +150 |
| `main.tf` | Update CoreDNS addon | +25 |
| `outputs.tf` | Add new outputs | +40 |
| `apps/wave-1-traefik.yaml` | Add tolerations | +10 |
| `apps/wave-3-prometheus-stack.yaml` | Add tolerations | +40 |
| `wave-1/karpenter/values.yaml` | Add tolerations | +10 |

**Total:** ~325 lines of changes across 8 files

**Effort:** 2-3 hours coding + 3-4 hours migration = **6-7 hours total**

**Risk:** 🟡 Medium - Zero downtime strategy with rollback, but requires careful execution

---

**Next Action:** Review this plan and approve for implementation
