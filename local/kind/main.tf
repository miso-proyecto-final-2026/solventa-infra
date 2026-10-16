# Raíz local: el MISMO módulo baseline que usa AWS, con entradas locales (research R4, FR-031).

module "service_list" {
  source = "../../modules/service-list"

  config = yamldecode(file("${path.module}/${var.services_file}"))
}

module "baseline" {
  source = "../../modules/baseline"

  services         = module.service_list.services
  reserved_schemas = module.service_list.reserved_schemas
  drop_schemas     = module.service_list.drop_schemas

  # Las imágenes se cargan con `kind load docker-image`; no hay registro ni comprobación de ECR.
  image_registry = ""

  secret_store = {
    kind      = "kubernetes"
    namespace = kubernetes_namespace_v1.local_secrets.metadata[0].name
  }

  db = {
    host             = "postgres.local-deps.svc"
    admin_secret_ref = kubernetes_secret_v1.pg_admin.metadata[0].name
    sslmode          = "disable"
  }

  cache = {
    scheme     = "redis"
    host       = "redis.local-deps.svc"
    secret_ref = null
  }

  service_db_secret_names    = { for name, s in kubernetes_secret_v1.service_db : name => s.metadata[0].name }
  service_db_secret_versions = { for name, s in kubernetes_secret_v1.service_db : name => sha256(jsonencode(nonsensitive(s.data))) }

  metrics_server_args = ["--kubelet-insecure-tls"]

  depends_on = [
    kubernetes_service_v1.postgres,
    kubernetes_deployment_v1.postgres,
    kubernetes_service_v1.redis,
    kubernetes_deployment_v1.redis,
  ]
}
