# Módulo auxiliar sin recursos: valida services.yaml (V1–V14, contrato C1) y lo normaliza
# para bootstrap, platform, baseline y local/kind (FR-022).

locals {
  services = {
    for s in var.config.services : s.name => merge(s, {
      role_name         = replace(s.name, "-", "_")
      cache_env_var     = s.cache_env_var == "" ? null : s.cache_env_var
      deploy_repository = coalesce(s.deploy_repository, "miso-proyecto-final-2026/${s.name}")
    })
  }

  schema_owner = merge([
    for s in var.config.services : { for schema in s.owned_schemas : schema => s.name }
  ]...)
}
