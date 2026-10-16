output "job_name" {
  description = "Nombre del Job db-access vigente (incluye el hash del SQL y de las versiones de secretos)."
  value       = kubernetes_job_v1.db_access.metadata[0].name
}

output "access_sql" {
  description = "SQL generado (sin contraseñas); útil para auditoría y pruebas."
  value       = local.access_sql
}

output "schema_owner" {
  description = "Mapa esquema => rol dueño."
  value       = local.schema_owner
}

output "done" {
  description = "Valor que depende de la finalización del Job (para depends_on)."
  value       = kubernetes_job_v1.db_access.id
}
