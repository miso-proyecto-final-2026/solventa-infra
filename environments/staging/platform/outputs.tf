# Contrato C4: ninguna salida contiene contraseñas, tokens ni cadenas de conexión.

output "region" {
  description = "Región AWS."
  value       = var.region
}

output "cluster_name" {
  description = "Nombre del clúster EKS."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint de la API de Kubernetes."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_data" {
  description = "CA del clúster (base64)."
  value       = module.eks.cluster_ca_data
}

output "registry_url" {
  description = "Registro ECR de la cuenta."
  value       = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "repositories" {
  description = "Mapa servicio => URL del repositorio ECR."
  value       = module.registry.repository_urls
}

output "db_endpoint" {
  description = "Host de PostgreSQL."
  value       = module.postgres.endpoint
}

output "db_port" {
  description = "Puerto de PostgreSQL."
  value       = module.postgres.port
}

output "db_name" {
  description = "Nombre de la base de datos."
  value       = module.postgres.database_name
}

output "db_admin_secret_arn" {
  description = "ARN del secreto maestro de RDS (solo referencia)."
  value       = module.postgres.admin_secret_arn
}

output "service_db_secret_names" {
  description = "Mapa servicio => nombre del secreto de BD (solo referencia)."
  value       = module.service_secrets.service_db_secret_names
}

output "service_db_secret_versions" {
  description = "Mapa servicio => version_id del secreto (entrada del hash del Job db-access)."
  value       = module.service_secrets.service_db_secret_versions
}

output "cache_secret_name" {
  description = "Nombre del secreto de caché (solo referencia)."
  value       = module.service_secrets.cache_secret_name
}

output "cache_primary_endpoint" {
  description = "Host primario de la caché."
  value       = module.redis.primary_endpoint
}

output "eso_pod_identity_role_arn" {
  description = "Rol de Pod Identity de External Secrets Operator."
  value       = module.eks.eso_pod_identity_role_arn
}

output "kyc_evidencias_bucket" {
  description = "Bucket de evidencias KYC (solo referencia)."
  value       = module.kyc_evidencias.bucket_name
}

output "polizas_bucket" {
  description = "Bucket de documentos de póliza (HU20; solo referencia); null si enable_events es false."
  value       = var.enable_events ? module.polizas_documentos[0].bucket_name : null
}

output "public_url" {
  description = "URL pública del borde (CloudFront); null si el borde está desactivado."
  value       = local.edge_enabled ? module.cloudfront[0].url : null
}

output "api_gateway_endpoint" {
  description = "Endpoint directo del API Gateway; el tráfico de clientes debe entrar por public_url."
  value       = local.edge_enabled ? module.api_gateway[0].api_endpoint : null
}

output "nlb_dns_name" {
  description = "DNS interno del NLB (solo alcanzable desde la VPC)."
  value       = local.edge_enabled ? module.nlb[0].dns_name : null
}

output "kafka_bootstrap_brokers" {
  description = "Brokers de MSK para clientes con SASL/IAM (puerto 9098). No es un secreto; null si enable_events es false."
  value       = one(module.msk[*].bootstrap_brokers_sasl_iam)
}

output "kafka_cluster_arn" {
  description = "ARN del clúster MSK; null si enable_events es false."
  value       = one(module.msk[*].cluster_arn)
}
