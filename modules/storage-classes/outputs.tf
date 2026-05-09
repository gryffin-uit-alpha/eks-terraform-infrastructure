output "default_storage_class" {
  description = "Default StorageClass name"
  value       = kubernetes_storage_class_v1.gp3_default.metadata[0].name
}

output "storage_class_gp3" {
  description = "GP3 StorageClass name"
  value       = kubernetes_storage_class_v1.gp3_default.metadata[0].name
}

output "storage_class_gp3_retain" {
  description = "GP3 Retain StorageClass name"
  value       = kubernetes_storage_class_v1.gp3_retain.metadata[0].name
}

output "storage_classes" {
  description = "List of all StorageClasses created"
  value = [
    kubernetes_storage_class_v1.gp3_default.metadata[0].name,
    kubernetes_storage_class_v1.gp3_retain.metadata[0].name
  ]
}
