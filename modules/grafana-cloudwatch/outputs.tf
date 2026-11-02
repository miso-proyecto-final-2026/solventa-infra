output "role_arn" {
  description = "ARN del rol de Pod Identity de Grafana."
  value       = aws_iam_role.grafana.arn
}
