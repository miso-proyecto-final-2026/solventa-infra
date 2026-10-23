output "deployments" {
  description = "Mapa servicio => nombre del Deployment."
  value       = { for k, w in module.workload : k => w.deployment_name }
}

output "migration_jobs" {
  description = "Mapa servicio => Job de migración."
  value       = { for k, w in module.workload : k => w.migration_job_name }
}

output "db_access_job" {
  description = "Job db-access vigente."
  value       = module.db_access.job_name
}

output "edge_node_ports" {
  description = "Mapa servicio => NodePort del borde (solo los servicios expuestos)."
  value       = { for k, w in module.workload : k => w.edge_node_port if w.edge_node_port != null }
}

output "kafka_topics_job" {
  description = "Job que crea los topics; null si no hay bus de eventos."
  value       = one(module.kafka_topics[*].job_name)
}
