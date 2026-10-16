# Job db-access (research R10): crea roles y esquemas desde dentro de la VPC, sin exponer la base.

locals {
  service_list = [for name, s in var.services : { name = name, role = s.role_name }]

  schema_owner = merge([
    for name, s in var.services : { for sc in s.owned_schemas : sc => s.role_name }
  ]...)

  all_schemas = sort(distinct(concat(var.reserved_schemas, keys(local.schema_owner), var.drop_schemas)))

  access_sql = templatefile("${path.module}/templates/access.sql.tftpl", {
    services       = local.service_list
    roles_array    = join(", ", [for s in local.service_list : "'${s.role}'"])
    all_schemas    = [for sc in local.all_schemas : sc if sc != "public" && !contains(var.drop_schemas, sc)]
    revoke_schemas = concat(["public"], [for sc in local.all_schemas : sc if sc != "public" && !contains(var.drop_schemas, sc)])
    schema_owner   = local.schema_owner
    drop_schemas   = var.drop_schemas
  })

  # Cualquier cambio en el SQL o en una contraseña genera un Job nuevo; sin cambios, no se re-ejecuta.
  job_hash = substr(sha256(join("|", [local.access_sql, jsonencode(var.service_db_secret_versions)])), 0, 10)
}

resource "kubernetes_config_map_v1" "access_sql" {
  metadata {
    name      = "db-access-sql-${local.job_hash}"
    namespace = var.namespace
  }

  data = {
    "access.sql" = local.access_sql
  }
}

resource "kubectl_manifest" "admin_secret" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "db-admin"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { kind = "ClusterSecretStore", name = var.secret_store_name }
      target          = { name = "db-admin", creationPolicy = "Owner" }
      data = [
        { secretKey = "PGUSER", remoteRef = { key = var.db.admin_secret_ref, property = "username" } },
        { secretKey = "PGPASSWORD", remoteRef = { key = var.db.admin_secret_ref, property = "password" } },
      ]
    }
  })
}

resource "kubectl_manifest" "service_passwords" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "db-access-passwords"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { kind = "ClusterSecretStore", name = var.secret_store_name }
      target          = { name = "db-access-passwords", creationPolicy = "Owner" }
      data = [
        for name, s in var.services : {
          secretKey = "PW_${s.role_name}"
          remoteRef = { key = var.service_db_secret_names[name], property = "password" }
        }
      ]
    }
  })
}

resource "kubernetes_job_v1" "db_access" {
  metadata {
    name      = "db-access-${local.job_hash}"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"      = "db-access"
      "app.kubernetes.io/component" = "platform"
    }
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "db-access"
        }
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name    = "psql"
          image   = var.image
          command = ["psql", "-v", "ON_ERROR_STOP=1", "-f", "/sql/access.sql"]

          env {
            name  = "PGHOST"
            value = var.db.host
          }

          env {
            name  = "PGPORT"
            value = tostring(var.db.port)
          }

          env {
            name  = "PGDATABASE"
            value = var.db.name
          }

          env {
            name  = "PGSSLMODE"
            value = var.db.sslmode
          }

          env_from {
            secret_ref {
              name = "db-admin"
            }
          }

          env_from {
            secret_ref {
              name = "db-access-passwords"
            }
          }

          volume_mount {
            name       = "sql"
            mount_path = "/sql"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "sql"
          config_map {
            name = kubernetes_config_map_v1.access_sql.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = var.job_timeout
    update = var.job_timeout
  }

  depends_on = [kubectl_manifest.admin_secret, kubectl_manifest.service_passwords]
}
