# ══════════════════════════════════════════════════════════════════════════════
# EBS CSI DRIVER IAM ROLE (IRSA)
# ══════════════════════════════════════════════════════════════════════════════
# The EBS CSI Driver needs AWS API permissions to:
# - Create EBS volumes
# - Attach/detach volumes to EC2 instances
# - Create/delete snapshots
# - Tag volumes
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "ebs_csi_driver" {
  count = local.create_oidc ? 1 : 0
  name  = "${local.name}-ebs-csi-driver"

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
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${local.name}-ebs-csi-driver"
  }
}

# AWS Managed Policy for EBS CSI Driver
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  count      = local.create_oidc ? 1 : 0
  role       = aws_iam_role.ebs_csi_driver[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Output for use in EBS CSI Driver Helm values
output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI Driver"
  value       = local.create_oidc ? aws_iam_role.ebs_csi_driver[0].arn : ""
}
