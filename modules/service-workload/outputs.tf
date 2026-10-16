output "deployment_name" {
  description = "Nombre del Deployment."
  value       = kubernetes_deployment_v1.this.metadata[0].name
}

output "service_name" {
  description = "Nombre del Service ClusterIP."
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "connection_secret_name" {
  description = "Secret generado por ESO con las variables de conexión."
  value       = local.connection_secret
}

output "migration_job_name" {
  description = "Nombre del Job de migración (null si el servicio no migra)."
  value       = local.has_migration ? kubernetes_job_v1.migrate[0].metadata[0].name : null
}
