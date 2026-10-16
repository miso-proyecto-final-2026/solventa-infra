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
