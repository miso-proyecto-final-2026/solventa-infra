output "staging_namespace" {
  description = "Namespace de las cargas de trabajo."
  value       = kubernetes_namespace_v1.staging.metadata[0].name
}

output "system_namespace" {
  description = "Namespace de componentes de plataforma."
  value       = kubernetes_namespace_v1.system.metadata[0].name
}

output "secret_store_name" {
  description = "Nombre del ClusterSecretStore."
  value       = var.secret_store.name
}

output "ready" {
  description = "Valor que depende de que ESO y su store estén instalados (para depends_on)."
  value       = kubectl_manifest.cluster_secret_store.id
}

output "monitoring_namespace" {
  description = "Namespace de Prometheus y Prometheus Adapter."
  value       = var.monitoring_namespace
}
