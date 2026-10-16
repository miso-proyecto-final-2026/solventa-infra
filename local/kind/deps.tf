# Dependencias locales en el clúster: PostgreSQL 16 y Redis 7 (sin AWS, FR-031).

resource "kubernetes_namespace_v1" "local_deps" {
  metadata {
    name = "local-deps"
  }
}

resource "kubernetes_secret_v1" "postgres_auth" {
  metadata {
    name      = "postgres-auth"
    namespace = kubernetes_namespace_v1.local_deps.metadata[0].name
  }

  data = {
    POSTGRES_PASSWORD = random_password.pg_admin.result
  }
}

resource "kubernetes_deployment_v1" "postgres" {
  #checkov:skip=CKV_K8S_28:Dependencia local desechable de kind (no es produccion)
  #checkov:skip=CKV_K8S_29:Dependencia local desechable de kind (no es produccion)
  #checkov:skip=CKV_K8S_30:Dependencia local desechable de kind (no es produccion)
  #checkov:skip=CKV_K8S_8:Dependencia local desechable de kind (no es produccion)
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.local_deps.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "postgres" }
    }

    template {
      metadata {
        labels = { app = "postgres" }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:16-alpine"

          env {
            name  = "POSTGRES_DB"
            value = "solventa"
          }

          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.postgres_auth.metadata[0].name
            }
          }

          port {
            container_port = 5432
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres", "-d", "solventa"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }

  wait_for_rollout = true
}

resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.local_deps.metadata[0].name
  }

  spec {
    selector = { app = "postgres" }

    port {
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_deployment_v1" "redis" {
  #checkov:skip=CKV_K8S_28:Dependencia local desechable de kind (no es produccion)
  #checkov:skip=CKV_K8S_29:Dependencia local desechable de kind (no es produccion)
  #checkov:skip=CKV_K8S_30:Dependencia local desechable de kind (no es produccion)
  #checkov:skip=CKV_K8S_8:Dependencia local desechable de kind (no es produccion)
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.local_deps.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "redis" }
    }

    template {
      metadata {
        labels = { app = "redis" }
      }

      spec {
        container {
          name  = "redis"
          image = "redis:7-alpine"

          port {
            container_port = 6379
          }

          readiness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }
        }
      }
    }
  }

  wait_for_rollout = true
}

resource "kubernetes_service_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.local_deps.metadata[0].name
  }

  spec {
    selector = { app = "redis" }

    port {
      port        = 6379
      target_port = 6379
    }
  }
}
