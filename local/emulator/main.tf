# Paso con emulador de API de AWS (Moto): aplica los módulos cuyos recursos Moto cubre bien (US2).
# No cubre EKS, RDS ni ElastiCache (Moto solo simula la API); esos se verifican con mocks, kind o AWS real
# (tabla de cobertura en el README, FR-032).

locals {
  tags = {
    Project     = "solventa"
    Environment = "emulator"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "platform"
  }
}

module "service_list" {
  source = "../../modules/service-list"

  config = yamldecode(file("${path.module}/../../environments/staging/services.yaml"))
}

# --- Bootstrap: bucket de estado y roles de CI --------------------------------------------------
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV2_AWS_6:Bucket desechable del emulador Moto
  #checkov:skip=CKV2_AWS_61:Bucket desechable del emulador Moto
  #checkov:skip=CKV_AWS_21:Bucket desechable del emulador Moto
  count = var.enable_ci_identities ? 1 : 0

  bucket        = "solventa-tfstate-emulator"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "state" {
  count = var.enable_ci_identities ? 1 : 0

  bucket = aws_s3_bucket.state[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

module "ci_identities" {
  count  = var.enable_ci_identities ? 1 : 0
  source = "../../modules/ci-identities"

  deploy_repositories = { for name, s in module.service_list.services : name => s.deploy_repository }
  state_bucket_name   = aws_s3_bucket.state[0].bucket
  # Moto no precarga las políticas gestionadas de AWS (ReadOnlyAccess, PowerUserAccess).
  attach_managed_policies = false
  tags                    = local.tags
}

# --- Plataforma: red, registro y secretos -------------------------------------------------------
module "network" {
  count  = var.enable_network ? 1 : 0
  source = "../../modules/network"

  tags = local.tags
}

module "registry" {
  source = "../../modules/registry"

  repositories = toset(keys(module.service_list.services))
  tags         = local.tags
}

resource "random_password" "cache_token" {
  length  = 32
  special = false
}

module "service_secrets" {
  source = "../../modules/service-secrets"

  services = { for name, s in module.service_list.services : name => { role_name = s.role_name } }

  # Las bases de datos y la caché no se emulan: valores ficticios solo para ejercitar el módulo.
  db_host          = "postgres.emulator.local"
  cache_host       = "cache.emulator.local"
  cache_auth_token = random_password.cache_token.result

  tags = local.tags
}
