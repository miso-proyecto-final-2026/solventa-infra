output "repositories" {
  description = "Repositorios ECR creados en el emulador."
  value       = module.registry.repository_urls
}

output "service_db_secret_names" {
  description = "Secretos de BD creados en el emulador (solo nombres)."
  value       = module.service_secrets.service_db_secret_names
}

output "network_vpc_id" {
  description = "VPC creada en el emulador (null si enable_network = false)."
  value       = one(module.network[*].vpc_id)
}
