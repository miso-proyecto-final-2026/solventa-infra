output "repository_urls" {
  description = "Mapa servicio => URL del repositorio ECR."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "Mapa servicio => ARN del repositorio ECR."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}
