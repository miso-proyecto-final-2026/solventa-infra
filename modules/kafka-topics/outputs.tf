output "all_topics" {
  description = "Todos los topics que crea el Job, incluidas las colas de mensajes fallidos."
  value       = local.all_topics
}

output "job_name" {
  description = "Nombre del Job vigente."
  value       = kubernetes_job_v1.topics.metadata[0].name
}
