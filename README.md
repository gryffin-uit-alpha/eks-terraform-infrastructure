# EKS Terraform Infrastructure

Production-grade AWS EKS cluster infrastructure with air-gapped local registry support.

## Architecture

This repository contains Terraform code for deploying:
- **bootstrap/** - S3 backend and DynamoDB lock table for remote state
- **Root modules** - VPC, EKS cluster, IAM, node groups, bastion registry, Karpenter & Velero infrastructure

## Key Features

- 🔒 **Air-gapped architecture**: All container images pulled through local EC2 registry
- 🏗️ **Modular design**: Reusable Terraform modules for each component
- 🔐 **Security-first**: IRSA for service accounts, private subnets, no public access
- 📦 **Remote state**: S3 backend with DynamoDB locking
- 🚀 **GitOps-ready**: Designed to work with ArgoCD App-of-Apps pattern

## Prerequisites

- Terraform >= 1.15
- AWS CLI configured with valid credentials
- Corporate proxy configured (if applicable)

## Quick Start

### 1. Bootstrap (First Time Only)

```bash
cd bootstrap
terraform init
terraform plan -var="state_bucket_name=YOUR-UNIQUE-BUCKET-NAME"
terraform apply -var="state_bucket_name=YOUR-UNIQUE-BUCKET-NAME"
```

### 2. Main Infrastructure

After bootstrap:

```bash
cd ..
# Update backend.tf with your bucket name from bootstrap output
terraform init
terraform plan
terraform apply
```

## Directory Structure

```
.
├── bootstrap/          # Remote state infrastructure
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── backend.tf          # S3 backend configuration (fill after bootstrap)
├── providers.tf        # AWS provider configuration
├── main.tf             # Root module composition
├── variables.tf        # Root input variables
├── outputs.tf          # Root outputs
└── user_data.sh.tpl    # Node group user data template
```

## Network Architecture

- **VPC**: 3 AZs with public and private subnets
- **NAT**: 1 NAT Gateway per AZ for HA
- **Registry**: EC2-hosted Docker registry in private subnet
- **EKS**: Private endpoint, nodes in private subnets only

## Important Notes

⚠️ **Registry Deadlock Prevention**: The registry MUST run on EC2, not as a Kubernetes Pod. Nodes cannot join without a registry, and a registry Pod cannot start without nodes.

⚠️ **Proxy Configuration**: If behind corporate proxy, ensure `insecure = true` is set in AWS provider for SSL interception.

## Related Repository

- [eks-gitops-patterns](https://github.com/gryffin-uit-alpha/eks-gitops-patterns) - ArgoCD manifests for cluster workloads

---

Built with ❤️ for production-grade EKS deployments
