locals {
  name = "${var.project_name}-${var.environment}"
}

# ── Amazon Linux 2023 AMI (latest) ───────────────────────────────────────────
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ── Security Group cho Bastion ────────────────────────────────────────────────
resource "aws_security_group" "bastion" {
  name        = "${local.name}-bastion-sg"
  description = "Security group for bastion EC2 running registry:2"
  vpc_id      = var.vpc_id

  # Inbound: only allow registry port from within VPC
  ingress {
    description = "Registry pull from within VPC"
    from_port   = var.registry_port
    to_port     = var.registry_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Outbound: internet access to pull and seed images into registry
  egress {
    description = "Allow all outbound for pulling images"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-bastion-sg" }
}

# ── User Data: cài Docker, chạy registry:2 như systemd service ───────────────
locals {
  registry_images = [
    # Core Kubernetes images
    "registry.k8s.io/pause:3.9",
    "registry.k8s.io/coredns/coredns:v1.11.1",
    "registry.k8s.io/kube-proxy:v1.30.0",
    # ArgoCD
    "quay.io/argoproj/argocd:v2.10.0",
    # Karpenter
    "public.ecr.aws/karpenter/controller:v0.37.0",
    # Traefik
    "docker.io/traefik:v3.0",
    # Kyverno
    "ghcr.io/kyverno/kyverno:v1.12.0",
    "ghcr.io/kyverno/background-controller:v1.12.0",
    "ghcr.io/kyverno/cleanup-controller:v1.12.0",
    "ghcr.io/kyverno/reports-controller:v1.12.0",
    # Velero
    "docker.io/velero/velero:v1.13.0",
    # Prometheus stack
    "quay.io/prometheus/prometheus:v2.51.0",
    "quay.io/prometheus/node-exporter:v1.7.0",
    "docker.io/grafana/grafana:10.4.0",
    # Metrics server
    "registry.k8s.io/metrics-server/metrics-server:v0.7.0",
  ]

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    registry_port   = var.registry_port
    registry_images = local.registry_images
  }))
}

# ── Bastion EC2 Instance ──────────────────────────────────────────────────────
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = var.instance_profile_name

  # Không dùng SSH key — access qua SSM Session Manager
  key_name = null

  # Bastion KHÔNG có public IP (private subnet)
  associate_public_ip_address = false

  user_data = local.user_data

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100 # 100GB để chứa images
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 bắt buộc
    http_put_response_hop_limit = 1
  }

  tags = { Name = "${local.name}-bastion-registry" }
}
