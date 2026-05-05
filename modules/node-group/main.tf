locals {
  name             = "${var.project_name}-${var.environment}"
  registry_address = "${var.local_registry_ip}:${var.local_registry_port}"

  # containerd config.toml với mirror cho tất cả public registries
  # Node sẽ pull từ local registry thay vì internet
  containerd_config = <<-CONTAINERD
    version = 2

    [plugins."io.containerd.grpc.v1.cri"]
      [plugins."io.containerd.grpc.v1.cri".containerd]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
            runtime_type = "io.containerd.runc.v2"
            [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
              SystemdCgroup = true

      [plugins."io.containerd.grpc.v1.cri".registry]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
          [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
            endpoint = ["http://${local.registry_address}"]
          [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
            endpoint = ["http://${local.registry_address}"]
          [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]
            endpoint = ["http://${local.registry_address}"]
          [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ghcr.io"]
            endpoint = ["http://${local.registry_address}"]
          [plugins."io.containerd.grpc.v1.cri".registry.mirrors."public.ecr.aws"]
            endpoint = ["http://${local.registry_address}"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs]
          [plugins."io.containerd.grpc.v1.cri".registry.configs."${local.registry_address}".tls]
            insecure_skip_verify = true
  CONTAINERD

  # User data: cấu hình containerd trước khi join cluster
  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -euo pipefail
    exec > >(tee /var/log/node-userdata.log) 2>&1

    echo "=== Cấu hình containerd mirror ==="
    mkdir -p /etc/containerd
    cat > /etc/containerd/config.toml <<'CONTAINERD_EOF'
    ${local.containerd_config}
    CONTAINERD_EOF

    systemctl restart containerd
    echo "=== containerd đã restart với local registry mirror ==="

    # Bootstrap node vào EKS cluster
    /etc/eks/bootstrap.sh '${var.cluster_name}'
  USERDATA
  )
}

# ── Security Group cho Worker Nodes ──────────────────────────────────────────
resource "aws_security_group" "nodes" {
  name        = "${local.name}-nodes-sg"
  description = "Security group cho EKS worker nodes"
  vpc_id      = var.vpc_id

  # Node-to-node communication
  ingress {
    description = "Node to node all ports"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Control plane to nodes
  ingress {
    description     = "Control plane to nodes"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [var.cluster_security_group_id]
  }

  # Kubelet API từ control plane
  ingress {
    description     = "Kubelet API"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [var.cluster_security_group_id]
  }

  # Pull từ local registry (bastion)
  egress {
    description = "Pull từ local registry"
    from_port   = var.local_registry_port
    to_port     = var.local_registry_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # HTTPS ra internet qua NAT (để gọi AWS API: EKS, EC2, SSM...)
  egress {
    description = "HTTPS to AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DNS
  egress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-nodes-sg" }
}

# ── Custom Launch Template ─────────────────────────────────────────────────────
resource "aws_launch_template" "nodes" {
  name        = "${local.name}-node-lt"
  description = "Launch template cho EKS nodes với containerd local registry mirror"

  image_id      = null # EKS Managed Node Group tự chọn AMI
  instance_type = null # Sẽ override trong node group

  user_data = local.user_data

  vpc_security_group_ids = [aws_security_group.nodes.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.disk_size_gb
      delete_on_termination = true
      encrypted             = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2          # 2 để Pod trong node có thể dùng IMDS
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                     = "${local.name}-node"
      "karpenter.sh/discovery" = var.cluster_name
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${local.name}-node-volume"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── EKS Managed Node Group ────────────────────────────────────────────────────
resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = "${local.name}-managed-ng"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  instance_types = var.instance_types

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable_percentage = 25
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  # Taint node group này là "on-demand base" để Karpenter scale spot
  taint {
    key    = "node-group"
    value  = "managed"
    effect = "NO_SCHEDULE"
  }

  labels = {
    role        = "managed-node"
    environment = var.environment
  }

  tags = { Name = "${local.name}-managed-ng" }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
