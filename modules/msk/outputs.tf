output "cluster_arn" {
  description = "ARN del clúster MSK."
  value       = aws_msk_cluster.this.arn
}

output "cluster_name" {
  description = "Nombre del clúster MSK."
  value       = aws_msk_cluster.this.cluster_name
}

output "bootstrap_brokers_sasl_iam" {
  description = "Brokers para clientes con SASL/IAM (puerto 9098). No es un secreto: solo funciona con una identidad autorizada."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
}

output "security_group_id" {
  description = "Security group de los brokers."
  value       = aws_security_group.this.id
}

output "client_role_arns" {
  description = "Rol de Pod Identity de cada servicio con acceso al bus, por nombre."
  value       = { for k, r in aws_iam_role.client : k => r.arn }
}

output "admin_role_arn" {
  description = "Rol del Job que crea los topics (puede crearlos y ajustarlos, pero no leer ni escribir eventos)."
  value       = aws_iam_role.admin.arn
}
