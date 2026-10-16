output "state_bucket" {
  description = "Bucket S3 con el estado remoto (variable TF_STATE_BUCKET)."
  value       = aws_s3_bucket.state.bucket
}

output "infra_plan_role_arn" {
  description = "Rol de plan de solo lectura (variable AWS_PLAN_ROLE_ARN)."
  value       = module.ci_identities.infra_plan_role_arn
}

output "infra_apply_role_arn" {
  description = "Rol de apply/destroy (variable AWS_APPLY_ROLE_ARN)."
  value       = module.ci_identities.infra_apply_role_arn
}

output "service_deploy_role_arns" {
  description = "Mapa servicio => rol de despliegue (variable AWS_ROLE_ARN en el repo del servicio)."
  value       = module.ci_identities.service_deploy_role_arns
}
