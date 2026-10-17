output "services" {
  description = "Servicios normalizados, indexados por nombre (incluye role_name y deploy_repository)."
  value       = local.services
}

output "shared_secret_names" {
  description = "Nombres de los secretos compartidos que declaran los servicios en secret_env_vars."
  value       = toset(flatten([for s in var.config.services : values(s.secret_env_vars)]))
}

output "reserved_schemas" {
  description = "Esquemas reservados sin dueño."
  value       = var.config.reserved_schemas
}

output "drop_schemas" {
  description = "Esquemas a eliminar de forma explícita (solo si no tienen dueño)."
  value       = var.config.drop_schemas
}

output "schema_owner" {
  description = "Mapa esquema => servicio dueño."
  value       = local.schema_owner
}
