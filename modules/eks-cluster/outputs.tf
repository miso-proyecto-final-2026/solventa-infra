output "cluster_name" {
  description = "Nombre del clúster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint de la API de Kubernetes."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_data" {
  description = "CA del clúster (base64)."
  value       = module.eks.cluster_certificate_authority_data
}

output "node_security_group_id" {
  description = "Security group de los nodos (origen permitido hacia RDS y ElastiCache)."
  value       = module.eks.node_security_group_id
}

output "eso_pod_identity_role_arn" {
  description = "Rol asociado a external-secrets/external-secrets mediante Pod Identity."
  value       = aws_iam_role.eso.arn
}
