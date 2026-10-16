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
