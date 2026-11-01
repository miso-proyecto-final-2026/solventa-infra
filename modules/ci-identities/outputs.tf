output "oidc_provider_arn" {
  description = "ARN del proveedor OIDC de GitHub usado por los roles."
  value       = local.oidc_provider_arn
}

output "infra_plan_role_arn" {
  description = "Rol de solo lectura para planes (PRs y main)."
  value       = aws_iam_role.infra_plan.arn
}

output "infra_apply_role_arn" {
  description = "Rol de apply/destroy (solo environment staging aprobado)."
  value       = aws_iam_role.infra_apply.arn
}

output "service_deploy_role_arns" {
  description = "Mapa servicio => ARN del rol de despliegue."
  value       = { for k, r in aws_iam_role.service_deploy : k => r.arn }
}

output "web_deploy_role_arn" {
  description = "Rol de despliegue de la consola web; null si no se pidió."
  value       = var.web_deploy_repository == null ? null : aws_iam_role.web_deploy[0].arn
}
