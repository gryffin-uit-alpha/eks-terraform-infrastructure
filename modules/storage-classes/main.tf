# ══════════════════════════════════════════════════════════════════════════════
# STORAGE CLASSES MODULE
# ══════════════════════════════════════════════════════════════════════════════
# Creates default gp3 StorageClass for EBS CSI Driver
# Ensures PVCs without storageClassName can bind automatically
# ══════════════════════════════════════════════════════════════════════════════

# ── GP3 Default StorageClass ──────────────────────────────────────────────────
resource "kubernetes_storage_class_v1" "gp3_default" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }
}

# ── GP3 Retain StorageClass ───────────────────────────────────────────────────
resource "kubernetes_storage_class_v1" "gp3_retain" {
  metadata {
    name = "gp3-retain"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "false"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain" # Volume survives PVC deletion
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }
}

# ── Remove default annotation from gp2 ────────────────────────────────────────
resource "null_resource" "fix_gp2_default" {
  triggers = {
    cluster_name = var.cluster_name
    gp3_created  = kubernetes_storage_class_v1.gp3_default.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for gp2 to appear (created by EKS addon)
      for i in {1..30}; do
        if kubectl get storageclass gp2 2>/dev/null; then
          echo "gp2 StorageClass found, removing default annotation..."
          kubectl patch storageclass gp2 \
            -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true
          break
        fi
        echo "Waiting for gp2 StorageClass... ($i/30)"
        sleep 5
      done
    EOT
  }

  depends_on = [
    kubernetes_storage_class_v1.gp3_default
  ]
}
