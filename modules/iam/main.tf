locals {
  name        = "${var.project_name}-${var.environment}"
  create_oidc = var.cluster_oidc_issuer_url != ""
}

# ── OIDC Provider (created after EKS cluster) ─────────────────────────────────
data "tls_certificate" "eks" {
  count = local.create_oidc ? 1 : 0
  url   = var.cluster_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks" {
  count           = local.create_oidc ? 1 : 0
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks[0].certificates[0].sha1_fingerprint]
  url             = var.cluster_oidc_issuer_url
}

locals {
  oidc_provider_arn = local.create_oidc ? aws_iam_openid_connect_provider.eks[0].arn : ""
  oidc_provider_url = local.create_oidc ? replace(var.cluster_oidc_issuer_url, "https://", "") : ""
}

# ── EKS Cluster IAM Role ──────────────────────────────────────────────────────
resource "aws_iam_role" "eks_cluster" {
  name = "${local.name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── EKS Node Group IAM Role ───────────────────────────────────────────────────
resource "aws_iam_role" "eks_node" {
  name = "${local.name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_container_registry" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# SSM access cho node (thay thế SSH)
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "eks_node" {
  name = "${local.name}-eks-node-profile"
  role = aws_iam_role.eks_node.name
}

# ── Karpenter IRSA ────────────────────────────────────────────────────────────
resource "aws_iam_role" "karpenter" {
  count = local.create_oidc ? 1 : 0
  name  = "${local.name}-karpenter-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:karpenter:karpenter"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "karpenter" {
  count       = local.create_oidc ? 1 : 0
  name        = "${local.name}-karpenter-policy"
  description = "Policy cho Karpenter node provisioning"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EC2 permissions để provision và manage nodes
      {
        Sid    = "Karpenter"
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:RunInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
      },
      # PassRole cho node IAM role
      {
        Sid      = "PassNodeIAMRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.eks_node.arn
      },
      # EKS Cluster read
      {
        Sid      = "EKSClusterEndpointLookup"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = "arn:aws:eks:*:${var.aws_account_id}:cluster/${var.cluster_name}"
      },
      # SQS interruption handling
      {
        Sid    = "KarpenterInterruption"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
        Resource = var.karpenter_sqs_queue_arn
      },
      # Instance profile cho Karpenter-provisioned nodes
      {
        Sid    = "AllowScopedInstanceProfileActions"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile"
        ]
        Resource = "arn:aws:iam::${var.aws_account_id}:instance-profile/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  count      = local.create_oidc ? 1 : 0
  role       = aws_iam_role.karpenter[0].name
  policy_arn = aws_iam_policy.karpenter[0].arn
}

# ── Velero IRSA ───────────────────────────────────────────────────────────────
resource "aws_iam_role" "velero" {
  count = local.create_oidc ? 1 : 0
  name  = "${local.name}-velero-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:velero:velero"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "velero" {
  count       = local.create_oidc ? 1 : 0
  name        = "${local.name}-velero-policy"
  description = "Policy cho Velero backup/restore tới S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VeleroS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = "${var.velero_bucket_arn}/*"
      },
      {
        Sid    = "VeleroS3Bucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = var.velero_bucket_arn
      },
      {
        Sid    = "VeleroEC2Snapshot"
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots",
          "ec2:DeleteSnapshot",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:CreateTags",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "velero" {
  count      = local.create_oidc ? 1 : 0
  role       = aws_iam_role.velero[0].name
  policy_arn = aws_iam_policy.velero[0].arn
}

# ── Bastion Instance Profile ───────────────────────────────────────────────────
resource "aws_iam_role" "bastion" {
  name = "${local.name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.name}-bastion-profile"
  role = aws_iam_role.bastion.name
}
