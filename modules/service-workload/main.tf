# Conjunto de objetos de un servicio en el namespace de cargas (data-model E7, research R11).

locals {
  image = var.image_registry == "" ? "${var.name}:${var.service.image_tag}" : "${var.image_registry}/${var.name}:${var.service.image_tag}"

  labels = {
    "app.kubernetes.io/name"       = var.name
    "app.kubernetes.io/part-of"    = "solventa"
    "app.kubernetes.io/managed-by" = "terraform"
  }

  # Los pods de migración NO deben coincidir con el selector del Deployment (`app.kubernetes.io/name = var.name`): el
  # HPA y el PDB usan ese selector, y un pod Succeeded dentro de él cuenta con métrica 0 y sin request de CPU (HA03).
  migration_labels = merge(local.labels, {
    "app.kubernetes.io/name"      = "${var.name}-migrate"
    "app.kubernetes.io/component" = "migration"
  })

  connection_secret = "${var.name}-connection"
  settings_map      = "${var.name}-settings"

  has_cache        = var.service.cache_env_var != null
  cache_has_secret = local.has_cache && var.cache.secret_ref != null

  # Contrato C2: los valores se componen en ESO; Terraform solo maneja referencias.
  db_url = "postgresql+psycopg://{{ .db_username }}:{{ .db_password }}@{{ .db_host }}:{{ .db_port }}/{{ .db_dbname }}${var.db_sslmode == "disable" ? "" : "?sslmode=${var.db_sslmode}"}"

  cache_url = (
    local.cache_has_secret
    ? "${var.cache.scheme}://:{{ .cache_auth_token }}@{{ .cache_host }}:{{ .cache_port }}/0"
    : "${var.cache.scheme}://${var.cache.host}:${var.cache.port}/0"
  )

  # Secretos compartidos entre servicios (p. ej. la clave de servicio): variable => nombre del secreto.
  # Cada uno es un secreto de una sola propiedad (`value`), generado en service-secrets.
  shared_secret_keys = { for env, name in var.service.secret_env_vars : env => "shared_${lower(env)}" }

  external_secret_data = concat(
    [for p in ["username", "password", "host", "port", "dbname"] : {
      secretKey = "db_${p}"
      remoteRef = { key = var.db_secret_name, property = p }
    }],
    local.cache_has_secret ? [for p in ["auth_token", "host", "port"] : {
      secretKey = "cache_${p}"
      remoteRef = { key = var.cache.secret_ref, property = p }
    }] : [],
    [for env, name in var.service.secret_env_vars : {
      secretKey = local.shared_secret_keys[env]
      remoteRef = { key = name, property = "value" }
    }],
  )

  external_secret_template = merge(
    { for v in var.service.database_env_vars : v => local.db_url },
    local.has_cache ? { (var.service.cache_env_var) = local.cache_url } : {},
    { for env, key in local.shared_secret_keys : env => "{{ .${key} }}" },
  )

  has_migration  = var.service.migration_command != null
  migration_hash = substr(sha256(jsonencode([local.image, var.service.migration_command])), 0, 8)
}

resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  automount_service_account_token = false
}

resource "kubernetes_config_map_v1" "settings" {
  metadata {
    name      = local.settings_map
    namespace = var.namespace
    labels    = local.labels
  }

  data = var.service.settings
}

resource "kubectl_manifest" "connection" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.connection_secret
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { kind = "ClusterSecretStore", name = var.secret_store_name }
      target = {
        name           = local.connection_secret
        creationPolicy = "Owner"
        template = {
          engineVersion = "v2"
          data          = local.external_secret_template
        }
      }
      data = local.external_secret_data
    }
  })
}

# ---------------------------------------------------------------------------
# Migraciones: plantilla suspendida (la usa CI, contrato C3) + Job que Terraform espera (FR-025)
# ---------------------------------------------------------------------------
resource "kubernetes_cron_job_v1" "migrate" {
  count = local.has_migration ? 1 : 0

  metadata {
    name      = "${var.name}-migrate"
    namespace = var.namespace
    labels    = local.migration_labels
  }

  spec {
    schedule                      = "0 0 31 2 *" # nunca se dispara: es una plantilla
    suspend                       = true
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = local.migration_labels
      }

      spec {
        backoff_limit              = 1
        ttl_seconds_after_finished = 86400

        template {
          metadata {
            labels = local.migration_labels
          }

          spec {
            restart_policy                  = "Never"
            service_account_name            = kubernetes_service_account_v1.this.metadata[0].name
            automount_service_account_token = false

            container {
              name    = "app"
              image   = local.image
              command = var.service.migration_command

              env_from {
                secret_ref {
                  name = local.connection_secret
                }
              }

              env_from {
                config_map_ref {
                  name = local.settings_map
                }
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    # CI actualiza la imagen de la plantilla antes de cada migración (SC-008).
    ignore_changes = [spec[0].job_template[0].spec[0].template[0].spec[0].container[0].image]
  }

  depends_on = [kubectl_manifest.connection, kubernetes_config_map_v1.settings]
}

resource "kubernetes_job_v1" "migrate" {
  count = local.has_migration ? 1 : 0

  metadata {
    name      = "${var.name}-migrate-${local.migration_hash}"
    namespace = var.namespace
    labels    = local.migration_labels
  }

  spec {
    backoff_limit = 1

    template {
      metadata {
        labels = local.migration_labels
      }

      spec {
        restart_policy                  = "Never"
        service_account_name            = kubernetes_service_account_v1.this.metadata[0].name
        automount_service_account_token = false

        container {
          name    = "app"
          image   = local.image
          command = var.service.migration_command

          env_from {
            secret_ref {
              name = local.connection_secret
            }
          }

          env_from {
            config_map_ref {
              name = local.settings_map
            }
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = var.migration_wait_timeout
    update = var.migration_wait_timeout
  }

  depends_on = [kubectl_manifest.connection, kubernetes_config_map_v1.settings]
}
