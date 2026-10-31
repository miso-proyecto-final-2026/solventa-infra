# Etapa platform: recursos AWS facturables de staging (VPC, EKS, ECR, RDS, ElastiCache, secretos).
# Los roles de CI viven en bootstrap/ y sobreviven al teardown (research R8).

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  cluster_name = "solventa-${var.name}"

  # E9: etiquetas obligatorias (FR-005), aplicadas por default_tags y por cada módulo.
  tags = {
    Project     = "solventa"
    Environment = var.name
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "platform"
  }

  # Roles de bootstrap, localizados por nombre determinista.
  apply_role_arn   = "arn:aws:iam::${local.account_id}:role/solventa-ci-infra-apply"
  plan_role_arn    = "arn:aws:iam::${local.account_id}:role/solventa-ci-infra-plan"
  deploy_role_arns = { for name, s in module.service_list.services : name => "arn:aws:iam::${local.account_id}:role/solventa-ci-deploy-${name}" }
}

locals {
  # Servicios con exposición pública (campo `edge` de services.yaml).
  edge_services = { for name, s in module.service_list.services : name => s if s.edge != null }
  edge_enabled  = var.enable_edge && length(local.edge_services) > 0
}

module "service_list" {
  source = "../../../modules/service-list"

  config = yamldecode(file("${path.module}/../services.yaml"))
}

module "network" {
  source = "../../../modules/network"

  name                   = local.cluster_name
  cluster_name           = local.cluster_name
  vpc_cidr               = var.vpc_cidr
  az_count               = var.az_count
  one_nat_gateway_per_az = var.one_nat_gateway_per_az
  tags                   = local.tags
}

module "registry" {
  source = "../../../modules/registry"

  repositories = toset(keys(module.service_list.services))
  tags         = local.tags
}

module "eks" {
  source = "../../../modules/eks-cluster"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids

  api_allowed_cidrs            = var.api_allowed_cidrs
  cluster_admin_principal_arns = distinct(concat([local.apply_role_arn], var.cluster_admin_principal_arns))
  plan_role_arn                = local.plan_role_arn
  deployer_role_arns           = local.deploy_role_arns

  node_instance_type           = var.node_instance_type
  node_count                   = var.node_count
  enable_control_plane_logging = var.enable_control_plane_logging
  db_admin_secret_arn          = module.postgres.admin_secret_arn

  tags = local.tags
}

# Evidencias KYC de MS Identidad (HU02): bucket cifrado, privado, solo TLS; el servicio solo escribe.
module "kyc_evidencias" {
  source = "../../../modules/evidence-bucket"

  bucket_name     = "solventa-${var.name}-kyc-evidencias-${local.account_id}"
  cluster_name    = module.eks.cluster_name
  service_account = "solventa-identidad"
  # Staging bajo demanda: solo guarda evidencias sintéticas y se destruye tras cada sesión.
  force_destroy = true

  tags = local.tags

  depends_on = [terraform_data.require_identidad]
}

# El bucket autoriza a la cuenta de servicio de MS Identidad: sin ese servicio no tiene sentido crearlo.
resource "terraform_data" "require_identidad" {
  lifecycle {
    precondition {
      condition     = contains(keys(module.service_list.services), "solventa-identidad")
      error_message = "services.yaml must define solventa-identidad: its service account writes the KYC evidence."
    }
  }
}

# Documentos de póliza de MS Suscripción (HU20, HU21): segunda instancia del módulo. El permiso (PutObject bajo polizas/ y
# firmadas/, GetObject sobre ambos) se adjunta al rol de MSK de Suscripción, porque EKS admite una sola asociación de Pod Identity por cuenta de
# servicio. Los objetos no expiran (las pólizas son documentos contractuales) y las versiones antiguas se conservan 30 días.
module "polizas_documentos" {
  count  = var.enable_events ? 1 : 0
  source = "../../../modules/evidence-bucket"

  bucket_name        = "solventa-${var.name}-polizas-${local.account_id}"
  cluster_name       = module.eks.cluster_name
  service_account    = "solventa-suscripcion"
  prefix             = "polizas/"
  existing_role_name = module.msk[0].client_role_names["solventa-suscripcion"]
  policy_name        = "documentos-polizas"
  # HU21: la copia firmada se guarda en firmadas/ y el servicio relee ambos PDF (comprueba el hash y los entrega).
  extra_write_prefixes = ["firmadas/"]
  read_access          = true
  retention_days       = null
  noncurrent_days      = 30
  # Staging bajo demanda: solo guarda documentos sintéticos y se destruye tras cada sesión.
  force_destroy = true

  tags = local.tags

  depends_on = [terraform_data.require_suscripcion]
}

# El permiso del bucket de pólizas va en el rol de MSK de Suscripción: sin ese servicio y sin eventos no tiene sentido crearlo.
resource "terraform_data" "require_suscripcion" {
  lifecycle {
    precondition {
      condition     = contains(keys(module.service_list.events_access), "solventa-suscripcion")
      error_message = "services.yaml must define solventa-suscripcion with eventos: the polizas bucket policy is attached to its MSK role."
    }
  }
}

module "postgres" {
  source = "../../../modules/postgres"

  name                      = "${local.cluster_name}-postgres"
  vpc_id                    = module.network.vpc_id
  subnet_ids                = module.network.private_subnet_ids
  allowed_security_group_id = module.eks.node_security_group_id

  instance_class         = var.db_instance_class
  multi_az               = var.db_multi_az
  backup_retention_days  = var.db_backup_retention_days
  deletion_protection    = var.db_deletion_protection
  final_snapshot_enabled = var.db_final_snapshot

  tags = local.tags
}

module "redis" {
  source = "../../../modules/redis"

  name                      = "${local.cluster_name}-cache"
  vpc_id                    = module.network.vpc_id
  subnet_ids                = module.network.private_subnet_ids
  azs                       = module.network.azs
  allowed_security_group_id = module.eks.node_security_group_id

  node_type = var.cache_node_type
  engine    = var.cache_engine
  replicas  = var.cache_replicas

  tags = local.tags
}

locals {
  # Qué topics produce y consume cada servicio de services.yaml, más la identidad de la prueba de humo (HS2).
  eventos_servicios = {
    for name, a in module.service_list.events_access : name => {
      namespace       = "staging"
      service_account = name
      produce         = a.produce
      consume         = a.consume
    }
  }
  eventos_humo = {
    "kafka-humo" = {
      namespace       = "solventa-system"
      service_account = "kafka-humo"
      produce         = ["solventa.humo"]
      consume         = ["solventa.humo"]
    }
  }
}

# Bus de eventos (HS2, ADR-0002): MSK privado, SASL/IAM, permisos mínimos por servicio. Factura por hora.
module "msk" {
  count  = var.enable_events ? 1 : 0
  source = "../../../modules/msk"

  # Del módulo de EKS (no de local.cluster_name): así Terraform crea el clúster antes que las asociaciones de Pod Identity.
  cluster_name              = module.eks.cluster_name
  vpc_id                    = module.network.vpc_id
  subnet_ids                = module.network.private_subnet_ids
  allowed_security_group_id = module.eks.node_security_group_id

  broker_node_type = var.events_broker_type
  broker_count     = var.az_count
  kafka_version    = var.events_kafka_version
  access           = merge(local.eventos_servicios, local.eventos_humo)

  tags = local.tags
}

module "service_secrets" {
  source = "../../../modules/service-secrets"

  services            = { for name, s in module.service_list.services : name => { role_name = s.role_name } }
  shared_secret_names = module.service_list.shared_secret_names

  db_host          = module.postgres.endpoint
  db_port          = module.postgres.port
  db_name          = module.postgres.database_name
  cache_host       = module.redis.primary_endpoint
  cache_port       = module.redis.port
  cache_auth_token = module.redis.auth_token

  secret_prefix = "solventa/${var.name}"
  tags          = local.tags
}

# Borde público según la arquitectura: CloudFront (TLS) + WAF → API Gateway → NLB interno → NodePort de cada servicio.
# Todo lo crea Terraform: el destroy no depende de Kubernetes ni deja balanceadores huérfanos.
module "nlb" {
  source = "../../../modules/nlb"
  count  = local.edge_enabled ? 1 : 0

  name                    = local.cluster_name
  vpc_id                  = module.network.vpc_id
  vpc_cidr                = var.vpc_cidr
  subnet_ids              = module.network.private_subnet_ids
  node_security_group_id  = module.eks.node_security_group_id
  autoscaling_group_names = module.eks.node_autoscaling_group_names
  services                = { for name, s in local.edge_services : name => { node_port = s.edge.node_port } }

  tags = local.tags
}

module "api_gateway" {
  source = "../../../modules/api-gateway"
  count  = local.edge_enabled ? 1 : 0

  name       = local.cluster_name
  vpc_id     = module.network.vpc_id
  vpc_cidr   = var.vpc_cidr
  subnet_ids = module.network.private_subnet_ids
  services = {
    for name, s in local.edge_services : name => {
      listener_arn  = module.nlb[0].listener_arns[name]
      node_port     = s.edge.node_port
      path_prefixes = s.edge.path_prefixes
      high_volume   = s.edge.high_volume
    }
  }

  high_volume_throttling_rate_limit  = var.edge_high_volume_throttling_rate_limit
  high_volume_throttling_burst_limit = var.edge_high_volume_throttling_burst_limit

  throttling_rate_limit  = var.edge_throttling_rate_limit
  throttling_burst_limit = var.edge_throttling_burst_limit

  tags = local.tags
}

module "cloudfront" {
  source = "../../../modules/cloudfront"
  count  = local.edge_enabled ? 1 : 0

  name              = local.cluster_name
  origin_domain     = module.api_gateway[0].domain_name
  enable_web        = true
  web_origin_domain = module.web_hosting[0].regional_domain_name
  allowed_countries = var.edge_allowed_countries

  rate_limit_per_5min = var.edge_rate_limit_per_5min

  # Rutas de los servicios `high_volume` (proveedores de eventos): quedan fuera del límite global por IP y tienen el suyo.
  high_volume_path_regex = join("|", [
    for name, s in local.edge_services : "^(${join("|", s.edge.path_prefixes)})(/.*)?$" if s.edge.high_volume
  ])
  high_volume_rate_limit_per_5min = var.edge_high_volume_rate_limit_per_5min

  tags = local.tags
}

# Consola web (HU39): archivos estáticos detrás de la misma distribución, con su WAF. El bucket solo lo lee CloudFront.
module "web_hosting" {
  source = "../../../modules/web-hosting"
  count  = local.edge_enabled ? 1 : 0

  bucket_name      = "solventa-${var.name}-web-${local.account_id}"
  distribution_arn = module.cloudfront[0].distribution_arn

  tags = local.tags
}
