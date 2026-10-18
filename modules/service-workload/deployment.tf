resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.service.replicas.min

    selector {
      match_labels = {
        "app.kubernetes.io/name" = var.name
      }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        service_account_name            = kubernetes_service_account_v1.this.metadata[0].name
        automount_service_account_token = false

        # ScheduleAnyway: permite reprogramar réplicas en la AZ superviviente durante el drill (research R11).
        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = {
              "app.kubernetes.io/name" = var.name
            }
          }
        }

        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = {
              "app.kubernetes.io/name" = var.name
            }
          }
        }

        container {
          name  = "app"
          image = local.image

          port {
            name           = "http"
            container_port = var.service.port
          }

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

          readiness_probe {
            http_get {
              path = var.service.health_path
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path = var.service.health_path
              port = "http"
            }
            initial_delay_seconds = 15
            period_seconds        = 20
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          resources {
            requests = var.service.resources.requests
            limits   = var.service.resources.limits
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = var.service.run_as_non_root

            capabilities {
              drop = ["ALL"]
            }

            seccomp_profile {
              type = "RuntimeDefault"
            }
          }
        }
      }
    }
  }

  lifecycle {
    # CI cambia la imagen y el HPA las réplicas: Terraform no debe revertirlas (FR-026, SC-008).
    ignore_changes = [
      spec[0].template[0].spec[0].container[0].image,
      spec[0].replicas,
    ]
  }

  # FR-025: la migración termina antes de crear o cambiar la carga.
  depends_on = [kubernetes_job_v1.migrate, kubectl_manifest.connection, kubernetes_config_map_v1.settings]
}

# Nunca LoadBalancer: el clúster no crea balanceadores que puedan bloquear el teardown (research R11).
resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name" = var.name
    }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
}

# Puerta de entrada del NLB (borde público): un NodePort fijo, sin crear ningún balanceador desde Kubernetes.
# El NLB lo crea Terraform en la etapa platform, así que el destroy no depende de un controlador (research R11).
resource "kubernetes_service_v1" "edge" {
  count = var.service.edge == null ? 0 : 1

  metadata {
    name      = "${var.name}-edge"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    type = "NodePort"

    selector = {
      "app.kubernetes.io/name" = var.name
    }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
      node_port   = var.service.edge.node_port
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    min_replicas = var.service.replicas.min
    max_replicas = var.service.replicas.max

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.this.metadata[0].name
    }

    metric {
      type = "Resource"

      resource {
        name = "cpu"

        target {
          type                = "Utilization"
          average_utilization = var.service.autoscaling.cpu_target_percent
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = 30
        select_policy                = "Max"

        policy {
          type           = "Pods"
          value          = 2
          period_seconds = 60
        }
      }

      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Max"

        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    min_available = "1"

    selector {
      match_labels = {
        "app.kubernetes.io/name" = var.name
      }
    }
  }
}
