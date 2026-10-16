output "primary_endpoint" {
  description = "Host del endpoint primario."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "port" {
  description = "Puerto de la caché."
  value       = aws_elasticache_replication_group.this.port
}

output "auth_token" {
  description = "Token de autenticación (solo para service-secrets; no se expone en las raíces)."
  value       = random_password.auth_token.result
  sensitive   = true
}

output "security_group_id" {
  description = "Security group de la caché."
  value       = aws_security_group.this.id
}
