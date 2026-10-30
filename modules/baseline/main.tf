# Composición del baseline en clúster (research R4): la misma para AWS y para kind.
# Orden: addons (ESO + store) → db-access → migración → Deployment (FR-025).

module "addons" {
  source = "../cluster-addons"

  secret_store        = var.secret_store
  metrics_server_args = var.metrics_server_args
  staging_namespace   = var.staging_namespace
  system_namespace    = var.system_namespace
}

# Logs y métricas en Grafana: tres pods y nada fuera del clúster. Comparte el namespace de Prometheus.
module "observability" {
  source = "../observability"
  count  = var.enable_observability ? 1 : 0

  namespace      = module.addons.monitoring_namespace
  log_namespaces = [module.addons.staging_namespace, module.addons.system_namespace]

  depends_on = [module.addons]
}

module "db_access" {
  source = "../db-access"

  services = {
    for name, s in var.services : name => {
      role_name     = s.role_name
      owned_schemas = s.owned_schemas
    }
  }

  reserved_schemas = var.reserved_schemas
  drop_schemas     = var.drop_schemas

  db                         = var.db
  secret_store_name          = module.addons.secret_store_name
  service_db_secret_names    = var.service_db_secret_names
  service_db_secret_versions = var.service_db_secret_versions
  namespace                  = module.addons.system_namespace

  depends_on = [module.addons]
}

# Topics del bus de eventos (HS2): un Job desde dentro de la VPC, antes que las cargas que los usan.
module "kafka_topics" {
  source = "../kafka-topics"
  count  = var.events == null ? 0 : 1

  bootstrap_servers = var.events.bootstrap_servers
  region            = var.events.region
  topics            = var.events.topics
  namespace         = module.addons.system_namespace

  depends_on = [module.addons]
}

module "workload" {
  source   = "../service-workload"
  for_each = var.services

  name      = each.key
  service   = each.value
  namespace = module.addons.staging_namespace

  image_registry    = var.image_registry
  secret_store_name = module.addons.secret_store_name
  db_secret_name    = var.service_db_secret_names[each.key]
  db_sslmode        = var.db.sslmode
  cache             = var.cache

  # El Job db-access crea el rol y los esquemas antes de que corra la migración; los topics existen antes de arrancar.
  depends_on = [module.db_access, module.kafka_topics]
}
