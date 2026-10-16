output "service_db_secret_names" {
  description = "Mapa servicio => nombre del secreto de BD (solo referencia)."
  value       = { for k, s in aws_secretsmanager_secret.service_db : k => s.name }
}

output "service_db_secret_arns" {
  description = "Mapa servicio => ARN del secreto de BD."
  value       = { for k, s in aws_secretsmanager_secret.service_db : k => s.arn }
}

output "service_db_secret_versions" {
  description = "Mapa servicio => version_id (entrada del hash del Job db-access)."
  value       = { for k, v in aws_secretsmanager_secret_version.service_db : k => v.version_id }
}

output "cache_secret_name" {
  description = "Nombre del secreto de caché (solo referencia)."
  value       = aws_secretsmanager_secret.cache.name
}
