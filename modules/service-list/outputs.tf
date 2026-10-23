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

output "topics" {
  description = "Topics declarados, por nombre, con particiones, retención, clave de partición y si tienen cola de mensajes fallidos."
  value       = { for t in var.config.topics : t.name => t }
}

output "topic_names" {
  description = "Nombres de todos los topics a crear, incluidas las colas de mensajes fallidos (<topic>.dlq)."
  value       = toset(flatten([for t in var.config.topics : t.dlq ? [t.name, "${t.name}.dlq"] : [t.name]]))
}

output "events_access" {
  description = "Qué topics produce y consume cada servicio que usa el bus; los servicios sin eventos no aparecen."
  value = {
    for s in var.config.services : s.name => s.eventos
    if length(concat(s.eventos.produce, s.eventos.consume)) > 0
  }
}
