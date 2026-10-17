# Etapa baseline: objetos dentro del clúster (add-ons, acceso a la BD, cargas de trabajo).
# Toda la lógica vive en modules/baseline; local/kind la reutiliza sin cambios (FR-031).

data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = var.platform_state_key
    region = var.region
  }
}

locals {
  platform = data.terraform_remote_state.platform.outputs
}

module "service_list" {
  source = "../../../modules/service-list"

  config = yamldecode(file("${path.module}/../services.yaml"))
}

locals {
  # Valores que salen de la plataforma (no se conocen al escribir services.yaml).
  platform_settings = {
    "solventa-identidad" = {
      KYC_EVIDENCIAS_BUCKET = local.platform.kyc_evidencias_bucket
      AWS_DEFAULT_REGION    = local.platform.region
    }
  }

  # image_tags permite fijar el SHA en ejecución sin editar services.yaml.
  services = {
    for name, s in module.service_list.services : name => merge(s, {
      image_tag = lookup(var.image_tags, name, s.image_tag)
      settings  = merge(s.settings, lookup(local.platform_settings, name, {}))
    })
  }
}

module "baseline" {
  source = "../../../modules/baseline"

  services         = local.services
  reserved_schemas = module.service_list.reserved_schemas
  drop_schemas     = module.service_list.drop_schemas

  image_registry = local.platform.registry_url

  secret_store = {
    kind   = "aws"
    region = local.platform.region
  }

  db = {
    host             = local.platform.db_endpoint
    port             = local.platform.db_port
    name             = local.platform.db_name
    admin_secret_ref = local.platform.db_admin_secret_arn
    sslmode          = "require"
  }

  cache = {
    scheme     = "rediss"
    host       = local.platform.cache_primary_endpoint
    secret_ref = local.platform.cache_secret_name
  }

  service_db_secret_names    = local.platform.service_db_secret_names
  service_db_secret_versions = local.platform.service_db_secret_versions
  metrics_server_args        = var.metrics_server_args

  # Ninguna carga cambia antes de comprobar que las imágenes existen.
  depends_on = [terraform_data.image_check]
}
