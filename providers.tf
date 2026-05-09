terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Workaround for corporate proxy with SSL interception
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = false

  # Aggressive retries for flaky corporate proxy
  max_retries = 10

  # Disable SSL verification (corporate proxy MITM)
  # WARNING: Only use behind trusted corporate proxy
  insecure = true

  # Custom retry configuration for proxy issues
  retry_mode = "adaptive"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ── Kubernetes Provider (for managing K8s resources via Terraform) ────────────
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  # Use AWS CLI to get authentication token
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}
