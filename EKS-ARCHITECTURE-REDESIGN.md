# EKS Architecture Redesign - Executive Summary

**Date:** 2026-05-07  
**Cluster:** eks-production  
**Status:** 🔴 REQUIRES REDESIGN - Single Node Group Architecture Inadequate

---

## Executive Summary

### Current State Assessment

**Infrastructure Status:**
- ✅ VPC networking functional (single NAT Gateway architecture)
- ⚠️ **CRITICAL ISSUE RESOLVED:** Security group rules for Service CIDR added (see `infra-scan/COMPLETE-FIX-SUMMARY.md`)
- 🔴 **ARCHITECTURE PROBLEM:** Single managed node group with mixed workloads creates operational risks

**Current Architecture Problems:**

| Issue | Impact | Severity |
|-------|--------|----------|
| Mixed workload scheduling | ArgoCD, monitoring, and apps compete for resources | 🔴 HIGH |
| No workload isolation | Noisy neighbors affect critical infrastructure | 🔴 HIGH |
| Generic taint strategy | Single `node-group=managed:NoSchedule` taint insufficient | 🟡 MEDIUM |
| Scaling conflicts | Cannot scale monitoring independently from apps | 🟡 MEDIUM |
| Resource contention | Prometheus memory spikes impact application performance | 🟡 MEDIUM |
| No HA guarantees | Critical services not isolated across failure domains | 🟡 MEDIUM |

---

## Proposed Architecture: Dedicated Node Groups

### Overview

Transform from **single shared node group** to **purpose-built node groups** with proper isolation:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        EKS Cluster: eks-production                   │
│                                                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │  SYSTEM-NG   │  │ MONITORING-NG│  │    APP-NG    │              │
│  │              │  │              │  │              │              │
│  │ • ArgoCD     │  │ • Prometheus │  │ • Backend    │              │
│  │ • Traefik    │  │ • Grafana    │  │ • Frontend   │              │
│  │ • cert-mgr   │  │ • Loki       │  │ • APIs       │              │
│  │ • external-  │  │ • AlertMgr   │  │              │              │
│  │   dns        │  │              │  │              │              │
│  │ • metrics-   │  │              │  │              │              │
│  │   server     │  │              │  │              │              │
│  │              │  │              │  │              │              │
│  │ Taint:       │  │ Taint:       │  │ Taint:       │              │
│  │ role=system  │  │ role=monitor │  │ role=app     │              │
│  │ :NoSchedule  │  │ :NoSchedule  │  │ :NoSchedule  │              │
│  │              │  │              │  │              │              │
│  │ Instance:    │  │ Instance:    │  │ Instance:    │              │
│  │ m7i-flex.    │  │ m7i-flex.    │  │ c7i-flex.    │              │
│  │ large        │  │ large        │  │ large        │              │
│  │              │  │              │  │              │              │
│  │ Min: 2       │  │ Min: 2       │  │ Min: 2       │              │
│  │ Max: 4       │  │ Max: 4       │  │ Max: 10      │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│                                                                       │
│  DaemonSets (aws-node, kube-proxy, node-exporter):                  │
│  → Tolerate ALL taints to run on every node                         │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Redesign Goals

### 1. Workload Isolation
- **System workloads** isolated from application noise
- **Monitoring stack** gets dedicated high-memory nodes
- **Applications** scale independently without affecting infrastructure

### 2. Predictable Scheduling
- Eliminate "pod pending" issues due to resource contention
- Guarantee infrastructure services always have capacity
- Enable autoscaling without scheduling conflicts

### 3. Cost Optimization
- Right-size instances per workload type
- Scale groups independently (don't over-provision)
- Use compute-optimized instances for apps, balanced for system/monitoring

### 4. High Availability
- Spread critical system pods across multiple nodes
- Anti-affinity rules ensure no single point of failure
- Multi-AZ distribution for all node groups

### 5. Operational Stability
- Prometheus memory spikes don't impact ArgoCD
- Application deployments don't destabilize ingress controller
- Clear blast radius for node failures

---

## Instance Type Selection Rationale

**Available types:** t3.micro, t3.small, c7i-flex.large, m7i-flex.large

### System Node Group: m7i-flex.large
**Why:**
- Balanced CPU/memory for diverse workloads (ArgoCD, Traefik, cert-manager)
- ArgoCD repo-server + application-controller require stable memory
- Traefik ingress needs consistent CPU for request routing
- 2 vCPU, 8 GB RAM sufficient for system components

**Not t3.small:**
- Burstable credit model unreliable for critical infrastructure
- ArgoCD + Traefik together exceed 4GB RAM under load
- CPU throttling would impact cluster management operations

### Monitoring Node Group: m7i-flex.large
**Why:**
- Prometheus requires high memory (2-4GB per replica)
- Grafana + Loki + AlertManager add memory pressure
- Time-series database writes are memory-intensive
- 8 GB RAM per node supports monitoring stack comfortably

**Not c7i-flex.large:**
- Monitoring is memory-bound, not CPU-bound
- Prometheus OOM kills are common with insufficient RAM
- Balanced instance type better for TSDB workloads

### Application Node Group: c7i-flex.large
**Why:**
- Applications typically CPU-bound (API processing, rendering)
- Compute-optimized provides best cost/performance for stateless apps
- 2 vCPU, 4 GB RAM suitable for microservices architecture
- Can scale to 10 nodes for high traffic periods

**Not m7i-flex.large:**
- Apps don't need 8GB RAM per instance
- Compute-optimized cheaper for CPU-heavy workloads
- Memory footprint for apps typically lower than system/monitoring

---

## Taint & Toleration Strategy

### System Node Group Taint
```yaml
taints:
  - key: role
    value: system
    effect: NoSchedule
```

**Workloads that must tolerate:**
- ArgoCD (all components)
- Traefik
- cert-manager
- external-dns
- metrics-server
- Kyverno

**DaemonSets that must tolerate:**
- aws-node (VPC CNI)
- kube-proxy
- node-exporter

### Monitoring Node Group Taint
```yaml
taints:
  - key: role
    value: monitoring
    effect: NoSchedule
```

**Workloads that must tolerate:**
- kube-prometheus-stack (Prometheus, Grafana, AlertManager)
- Loki
- Grafana Loki

**DaemonSets that must tolerate:**
- aws-node
- kube-proxy
- node-exporter

### Application Node Group Taint
```yaml
taints:
  - key: role
    value: app
    effect: NoSchedule
```

**Workloads that must tolerate:**
- All application deployments (backend, frontend, APIs)

**DaemonSets that must tolerate:**
- aws-node
- kube-proxy
- node-exporter

### DaemonSet Toleration Requirements

**CRITICAL:** DaemonSets must tolerate ALL custom taints to ensure cluster networking functions:

```yaml
# Example: aws-node DaemonSet must have
tolerations:
  - operator: Exists  # Tolerates ALL taints
```

**Why:** 
- VPC CNI (aws-node) must run on every node for pod networking
- kube-proxy must run on every node for Service routing
- node-exporter must run on every node for monitoring

**Without these tolerations:**
- ❌ Pods on tainted nodes cannot communicate
- ❌ Services don't work on tainted nodes
- ❌ No metrics collected from tainted nodes

---

## Node Group Specifications

### system-ng
```hcl
name          = "system-ng"
instance_types = ["m7i-flex.large"]
desired_size  = 2
min_size      = 2
max_size      = 4
disk_size_gb  = 50

taints = [{
  key    = "role"
  value  = "system"
  effect = "NO_SCHEDULE"
}]

labels = {
  role        = "system"
  workload    = "infrastructure"
  environment = "production"
}
```

**Capacity Planning:**
- ArgoCD: 1 GB RAM, 0.5 CPU
- Traefik: 0.5 GB RAM, 0.5 CPU
- cert-manager: 0.25 GB RAM, 0.1 CPU
- external-dns: 0.25 GB RAM, 0.1 CPU
- metrics-server: 0.5 GB RAM, 0.2 CPU
- **Total per node:** ~2.5 GB RAM, 1.4 CPU
- **Headroom:** 5.5 GB RAM, 0.6 CPU available

### monitoring-ng
```hcl
name          = "monitoring-ng"
instance_types = ["m7i-flex.large"]
desired_size  = 2
min_size      = 2
max_size      = 4
disk_size_gb  = 50

taints = [{
  key    = "role"
  value  = "monitoring"
  effect = "NO_SCHEDULE"
}]

labels = {
  role        = "monitoring"
  workload    = "observability"
  environment = "production"
}
```

**Capacity Planning:**
- Prometheus (replica): 3 GB RAM, 1 CPU
- Grafana: 0.5 GB RAM, 0.2 CPU
- AlertManager: 0.25 GB RAM, 0.1 CPU
- **Total per node:** ~3.75 GB RAM, 1.3 CPU
- **Headroom:** 4.25 GB RAM, 0.7 CPU available

### app-ng
```hcl
name          = "app-ng"
instance_types = ["c7i-flex.large"]
desired_size  = 2
min_size      = 2
max_size      = 10
disk_size_gb  = 50

taints = [{
  key    = "role"
  value  = "app"
  effect = "NO_SCHEDULE"
}]

labels = {
  role        = "application"
  workload    = "app"
  environment = "production"
}
```

**Capacity Planning:**
- Flexible - depends on application deployments
- Can scale from 2 to 10 nodes based on load
- Each node: 2 vCPU, 4 GB RAM

---

## Networking Considerations

### Cross-Node Group Communication

**VERIFIED:** All node groups in same VPC (10.0.0.0/16) with unified security group rules:

```hcl
# Security Group: eks-cluster-production-nodes-sg
# Applies to ALL node groups

ingress {
  description = "Pod to pod across nodes (VPC CIDR)"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["10.0.0.0/16"]  # Covers all node groups
}

ingress {
  description = "Kubernetes Service CIDR - pod-to-service TCP"
  from_port   = 0
  to_port     = 65535
  protocol    = "tcp"
  cidr_blocks = ["172.20.0.0/16"]  # Service CIDR
}
```

**Result:**
- ✅ Pods on system-ng can reach pods on app-ng
- ✅ Traefik (system-ng) can route to apps (app-ng)
- ✅ Prometheus (monitoring-ng) can scrape apps (app-ng)
- ✅ ArgoCD (system-ng) can manage workloads on all node groups

### DNS Resolution

**CoreDNS Placement:**
- Deploy CoreDNS on **system-ng** (infrastructure component)
- Add toleration for `role=system:NoSchedule`
- Ensure 2 replicas for HA

**Why system-ng:**
- DNS is cluster infrastructure, not application workload
- Must be stable and isolated from application noise
- Co-located with other cluster services

---

## High Availability Strategy

### System Node Group HA
```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: argocd-server
          topologyKey: topology.kubernetes.io/zone
```

**Result:** ArgoCD components spread across us-east-1a, 1b, 1c

### Monitoring Node Group HA
```yaml
prometheus:
  prometheusSpec:
    replicas: 2
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: prometheus
            topologyKey: topology.kubernetes.io/zone
```

**Result:** Prometheus replicas on different AZs, survive zone failure

### Application Node Group HA
- Min 2 nodes across different AZs
- Application deployments should specify `replicas: 2+` with anti-affinity
- Autoscaling responds to CPU/memory pressure

---

## DaemonSet Compatibility

### Critical DaemonSets

**aws-node (VPC CNI):**
```yaml
tolerations:
  - operator: Exists  # Must run on ALL nodes regardless of taints
```

**kube-proxy:**
```yaml
tolerations:
  - operator: Exists  # Must run on ALL nodes for Service networking
```

**node-exporter:**
```yaml
tolerations:
  - operator: Exists  # Must run on ALL nodes for metrics collection
```

**Verification Required:**
After applying new taints, check DaemonSet pod count:
```bash
kubectl get ds -n kube-system aws-node -o wide
# Expected: DESIRED = CURRENT = READY = total node count (6 in proposed architecture)
```

---

## Migration Strategy

### Phase 1: Create New Node Groups (Zero Downtime)
1. Add `system-ng` module to Terraform
2. Add `monitoring-ng` module to Terraform
3. Add `app-ng` module to Terraform
4. Apply Terraform (new node groups created, old remains)
5. **Total nodes:** 8 (2 old + 6 new)

### Phase 2: Migrate Workloads
1. Update ArgoCD Application manifests with tolerations
2. Update Prometheus Helm values with tolerations
3. Update application Helm charts with tolerations
4. Trigger rolling restart to reschedule pods
5. Verify pods land on correct node groups

### Phase 3: Decommission Old Node Group
1. Cordon old nodes: `kubectl cordon <node>`
2. Drain old nodes: `kubectl drain <node> --ignore-daemonsets`
3. Delete old node group via Terraform
4. **Total nodes:** 6 (system-ng: 2, monitoring-ng: 2, app-ng: 2)

### Rollback Plan
If issues arise:
```bash
# Revert Terraform to previous state
cd eks-terraform-infrastructure
git revert HEAD
terraform apply

# Old node group restored, new node groups can be destroyed
```

---

## Cost Analysis

### Current Architecture (Single Node Group)
```
Instance: t3.small
Nodes: 2
Cost: 2 × $0.0208/hr × 730 hr/mo = $30.37/month
```

### Proposed Architecture (Three Node Groups)
```
system-ng:      2 × m7i-flex.large × $0.0945/hr × 730 = $137.97/mo
monitoring-ng:  2 × m7i-flex.large × $0.0945/hr × 730 = $137.97/mo
app-ng:         2 × c7i-flex.large × $0.0918/hr × 730 = $133.83/mo

Total Base: $409.77/month
Total Max (app-ng scaled to 10): $943.47/month
```

**Cost Increase:** $379.40/month base (~12.5x)

**Justification:**
- **Operational stability:** Eliminate downtime from resource contention
- **Predictable scaling:** Right-sized instances prevent over-provisioning
- **Production readiness:** Current t3.small architecture not suitable for production
- **Cost avoidance:** Prevent outages from mixed workload conflicts

**Cost Optimization Opportunities:**
- Use Savings Plans for m7i/c7i instances (30-40% discount)
- Implement Karpenter for spot instances on app-ng (60-70% savings)
- Right-size after monitoring actual usage patterns

---

## Related Documents

- `infra-scan/COMPLETE-FIX-SUMMARY.md` - Security group fixes (Service CIDR)
- `infra-scan/ROOT_CAUSE_ANALYSIS.md` - Initial ArgoCD connectivity analysis
- `infra-scan/ACTUAL-ROOT-CAUSE.md` - Cross-node pod communication diagnosis

---

## Next Steps

1. **Review this redesign** - Validate node group strategy and instance types
2. **Review detailed implementation plan** - See `TERRAFORM-REFACTOR-PLAN.md` (to be created)
3. **Create node group modules** - Refactor Terraform for multiple node groups
4. **Update workload tolerations** - Modify ArgoCD Applications for new taints
5. **Execute migration** - Zero-downtime rollout with rollback capability

---

**Status:** 📋 Design Complete - Awaiting Approval for Implementation  
**Risk Level:** 🟡 Medium - Requires careful migration but fully reversible  
**Estimated Implementation Time:** 4-6 hours (Terraform + migration + testing)
