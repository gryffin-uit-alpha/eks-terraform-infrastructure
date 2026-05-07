# EKS Architecture Redesign & Infrastructure Audit Task

You are a senior Kubernetes + AWS EKS + Terraform infrastructure architect.

Your task is to FULLY inspect, audit, analyze, and redesign the current EKS infrastructure inside this repository.

DO NOT make assumptions.
DO NOT immediately modify Terraform.
FIRST perform a complete infrastructure discovery and architecture analysis.

---

# PRIMARY GOALS

1. Scan and understand the ENTIRE current infrastructure.
2. Identify:
   - network issues
   - scheduling risks
   - HA risks
   - scaling problems
   - security weaknesses
   - GitOps/ArgoCD deployment issues
   - node isolation problems
   - bad taint/toleration design
   - addon placement issues
   - subnet/NAT/VPC issues
   - EKS endpoint accessibility issues
   - CoreDNS/networking risks
   - future operational bottlenecks
3. Redesign the EKS architecture using dedicated node groups.
4. Ensure workloads are isolated correctly.
5. Ensure ALL nodes and workloads can still communicate correctly across the cluster.
6. Ensure DaemonSets continue functioning correctly after taints are applied.
7. Produce a comparison between CURRENT vs PROPOSED architecture.
8. Explain WHY every architectural decision is made.

---

# IMPORTANT CONSTRAINTS

Available EC2 instance types ONLY:

- t3.micro
- t3.small
- c7i-flex.large
- m7i-flex.large

You MUST optimize:
- cost
- stability
- scalability
- scheduling reliability
- HA
- networking
- GitOps reliability
- observability reliability

---

# VERY IMPORTANT REQUIREMENTS

## 1. FULL INFRASTRUCTURE DISCOVERY

You MUST scan ALL of the following:

### Terraform
- modules
- providers
- backend
- variables
- outputs
- node groups
- VPC
- subnets
- route tables
- NAT gateways
- security groups
- IAM
- EKS cluster config
- addons
- launch templates
- autoscaling config
- taints
- labels
- tolerations
- Helm releases
- ArgoCD manifests

### Kubernetes
Inspect:
- nodes
- taints
- labels
- namespaces
- deployments
- daemonsets
- statefulsets
- ingress
- services
- network policies
- storage classes
- CoreDNS
- kube-proxy
- aws-node CNI
- metrics-server
- ArgoCD
- monitoring stack

### Networking
You MUST inspect:
- pod-to-pod communication
- cross-node communication
- DNS resolution
- kube-dns/CoreDNS health
- VPC CNI configuration
- subnet IP exhaustion risks
- ENI limits
- security group rules
- public/private subnet design
- internet access path
- NAT dependency risks
- EKS endpoint accessibility
- node bootstrap reliability

---

# DESIGN REQUIREMENTS

You MUST redesign the cluster using dedicated node groups.

Proposed architecture should contain:

## 1. system-ng
Purpose:
- ArgoCD
- cert-manager
- external-dns
- ingress controller
- metrics-server
- cluster critical services

Requirements:
- dedicated taint
- isolated from application workloads
- stable on-demand nodes only
- high reliability
- avoid noisy neighbors

Preferred instances:
- t3.small OR m7i-flex.large depending on sizing analysis

---

## 2. monitoring-ng
Purpose:
- Prometheus
- Grafana
- Loki
- monitoring/logging stack

Requirements:
- isolated due to high memory/IO usage
- avoid interference with applications
- stable scheduling
- persistent workloads considerations

Preferred instances:
- m7i-flex.large

---

## 3. app-ng
Purpose:
- backend
- frontend
- APIs
- normal application workloads

Requirements:
- scalable
- balanced cost/performance
- no infrastructure workloads mixed

Preferred instances:
- c7i-flex.large

---

## 4. optional-spot-ng (ONLY if architecture supports it safely)
Purpose:
- CI runners
- batch jobs
- stateless workers

Requirements:
- MUST NOT host critical infrastructure
- MUST explain interruption handling strategy
- MUST explain risks

---

# TAINT/TOLERATION REQUIREMENTS

You MUST:
- design proper taints
- design tolerations
- ensure applications schedule correctly
- ensure infra workloads are isolated
- ensure DaemonSets continue scheduling correctly

CRITICAL:
DaemonSets such as:
- aws-node
- kube-proxy
- monitoring agents
- node exporters

MUST continue functioning across ALL required nodes.

You MUST explain:
- how DaemonSets bypass taints
- which tolerations are required
- risks if misconfigured

---

# NETWORKING REQUIREMENTS

You MUST ensure:
- cross-node pod communication works correctly
- services communicate across node groups
- ingress can route traffic correctly
- DNS resolution works cluster-wide
- ArgoCD can reach repositories
- monitoring stack can scrape workloads
- kube-dns/CoreDNS remain highly available

You MUST explicitly verify:
- no taint accidentally blocks cluster networking
- no node isolation breaks service discovery
- no subnet routing issue exists
- no security group prevents communication

---

# ARGOCD REQUIREMENTS

You MUST investigate WHY ArgoCD may not be reading repositories correctly.

Inspect:
- networking
- DNS
- outbound internet access
- IAM
- repo-server logs
- Redis connectivity
- ingress connectivity
- TLS/cert issues
- GitHub reachability
- security groups
- proxy issues
- CoreDNS

You MUST provide:
- root cause analysis
- evidence
- fixes
- Terraform/Kubernetes changes required

---

# REQUIRED OUTPUTS

Generate:

## 1. Current Architecture Report
Include:
- node groups
- workload placement
- network topology
- addons
- risks
- weaknesses

---

## 2. Proposed Architecture
Include:
- node group layout
- taints
- tolerations
- labels
- instance sizing
- HA strategy
- scheduling strategy
- scaling strategy

---

## 3. Current vs Proposed Comparison
Explain:
- what changes
- why it changes
- benefits
- tradeoffs
- risks reduced

---

## 4. Security & Reliability Findings
Explain:
- blast radius improvements
- isolation improvements
- scheduling improvements
- networking improvements
- GitOps stability improvements

---

## 5. Terraform Refactor Plan
Explain:
- what Terraform modules/files must change
- what resources should be added/removed
- migration risks
- rollout strategy
- zero downtime considerations

---

# EXECUTION RULES

1. NEVER assume the cluster is healthy.
2. VERIFY EVERYTHING.
3. INSPECT BEFORE MODIFYING.
4. AFTER every finding:
   - explain evidence
   - explain impact
   - explain fix
5. DO NOT immediately apply changes.
6. Produce the full analysis FIRST.
7. Think like:
   - SRE
   - Platform Engineer
   - Kubernetes Architect
   - Cloud Security Engineer

The final output must be extremely detailed, production-grade, and focused on long-term maintainability and operational stability.