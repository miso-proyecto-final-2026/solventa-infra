output "deployments" {
  description = "Mapa servicio => nombre del Deployment."
  value       = module.baseline.deployments
}

output "migration_jobs" {
  description = "Mapa servicio => Job de migración."
  value       = module.baseline.migration_jobs
}

output "db_access_job" {
  description = "Job db-access vigente."
  value       = module.baseline.db_access_job
}

output "edge_node_ports" {
  description = "Mapa servicio => NodePort del borde (el NLB de platform apunta a estos puertos)."
  value       = module.baseline.edge_node_ports
}
