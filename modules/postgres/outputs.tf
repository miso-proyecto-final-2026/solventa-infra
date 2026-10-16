output "endpoint" {
  description = "Host del endpoint de PostgreSQL."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Puerto de PostgreSQL."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Nombre de la base de datos compartida."
  value       = aws_db_instance.this.db_name
}

output "admin_secret_arn" {
  description = "ARN del secreto maestro gestionado por RDS (solo referencia)."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

output "security_group_id" {
  description = "Security group de la base de datos."
  value       = aws_security_group.this.id
}
