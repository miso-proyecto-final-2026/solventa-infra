output "grafana_service" {
  description = "Service de Grafana (ClusterIP; se abre con `kubectl port-forward`, no se publica)."
  value       = "grafana"
}

output "grafana_namespace" {
  description = "Namespace de Grafana."
  value       = var.namespace
}

output "loki_url" {
  description = "URL interna de Loki."
  value       = local.loki_url
}

output "loki_storage" {
  description = "Dónde guarda Loki los logs: `s3` (sobreviven a reinicios) o `filesystem` (disco del nodo)."
  value       = local.loki_store
}

output "grafana_url" {
  description = "URL pública de Grafana (con login); null si solo se abre con port-forward."
  value       = local.grafana_public ? "https://${local.grafana_host}${local.grafana_subpath}/" : null
}
