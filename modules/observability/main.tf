# Logs y métricas en Grafana con la menor infraestructura posible (staging): tres pods y nada fuera del clúster.
#
#   pods (stdout) --API de Kubernetes--> Alloy (1 pod) --> Loki (1 pod, disco efímero) --> Grafana <-- Prometheus (ya existe)
#
# Decisiones de costo, todas deliberadas:
# - Alloy es un único Deployment que lee los logs por la API de Kubernetes, no un DaemonSet por nodo.
# - Loki guarda en un emptyDir: sin PVC, sin bucket y sin roles de AWS, así que el destroy no deja nada.
#   A cambio, los logs se pierden si el pod de Loki se reinicia; la retención corta mantiene el disco acotado.
# - Grafana no persiste nada: fuentes de datos y dashboards se aprovisionan desde este módulo.
# - Sin Ingress ni Service público: se abre con `kubectl port-forward`. La contraseña de admin la genera el chart
#   (Secret `grafana` del namespace); nunca pasa por Terraform ni por el estado.

locals {
  loki_url = "http://loki.${var.namespace}.svc:3100"

  dashboards = {
    logs      = file("${path.module}/dashboards/logs.json")
    servicios = file("${path.module}/dashboards/servicios.json")
  }

  # `loki.source.kubernetes` lee los logs por la API (sin DaemonSet). Las etiquetas son pocas a propósito: cada
  # combinación crea un flujo en Loki. El resto (trace_id, correlation_id) queda dentro de la línea y se filtra con `| json`.
  alloy_config = <<-EOT
    discovery.kubernetes "pods" {
      role = "pod"
      namespaces {
        names = ${jsonencode(var.log_namespaces)}
      }
    }

    discovery.relabel "pods" {
      targets = discovery.kubernetes.pods.targets

      rule {
        source_labels = ["__meta_kubernetes_namespace"]
        target_label  = "namespace"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_name"]
        target_label  = "pod"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_container_name"]
        target_label  = "container"
      }
      // Los Deployments llevan app.kubernetes.io/name; los Jobs (migraciones, db-access) caen al nombre del Job.
      rule {
        source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
        target_label  = "service"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_label_job_name"]
        regex         = "(.+)"
        target_label  = "service"
      }
    }

    loki.source.kubernetes "pods" {
      targets    = discovery.relabel.pods.output
      forward_to = [loki.process.niveles.receiver]
    }

    // Los servicios con logs JSON exponen `level`; los de texto plano pasan sin etiqueta de nivel.
    loki.process "niveles" {
      stage.json {
        expressions = { level = "level" }
      }
      stage.labels {
        values = { level = "" }
      }
      forward_to = [loki.write.loki.receiver]
    }

    loki.write "loki" {
      endpoint {
        url = "${local.loki_url}/loki/api/v1/push"
      }
    }
  EOT
}

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = var.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version

  values = [yamlencode({
    deploymentMode = "SingleBinary"

    loki = {
      auth_enabled = false

      commonConfig = {
        replication_factor = 1
        path_prefix        = "/var/loki"
      }

      schemaConfig = {
        configs = [{
          from         = "2024-04-01"
          store        = "tsdb"
          object_store = "filesystem"
          schema       = "v13"
          index = {
            prefix = "index_"
            period = "24h"
          }
        }]
      }

      storage = { type = "filesystem" }

      limits_config = {
        retention_period           = var.log_retention
        reject_old_samples         = true
        reject_old_samples_max_age = var.log_retention
      }

      compactor = {
        working_directory      = "/var/loki/compactor"
        retention_enabled      = true
        delete_request_store   = "filesystem"
        retention_delete_delay = "2h"
      }
    }

    singleBinary = {
      replicas    = 1
      persistence = { enabled = false }
      # Sin PVC el chart no monta /var/loki: se monta un disco efímero acotado.
      extraVolumes      = [{ name = "storage", emptyDir = { sizeLimit = var.loki_storage_limit } }]
      extraVolumeMounts = [{ name = "storage", mountPath = "/var/loki" }]
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }

    # Modo escalable apagado: solo el binario único.
    read    = { replicas = 0 }
    write   = { replicas = 0 }
    backend = { replicas = 0 }

    gateway      = { enabled = false }
    chunksCache  = { enabled = false }
    resultsCache = { enabled = false }
    lokiCanary   = { enabled = false }
    test         = { enabled = false }
    sidecar      = { rules = { enabled = false } }
    monitoring = {
      selfMonitoring = { enabled = false }
      serviceMonitor = { enabled = false }
    }
  })]

  wait = true
}

resource "helm_release" "alloy" {
  name       = "alloy"
  namespace  = var.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.alloy_chart_version

  values = [yamlencode({
    controller = {
      type     = "deployment"
      replicas = 1
    }

    alloy = {
      configMap = { content = local.alloy_config }
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
    }
  })]

  wait       = true
  depends_on = [helm_release.loki]
}

resource "helm_release" "grafana" {
  name      = "grafana"
  namespace = var.namespace
  # El chart de grafana/helm-charts está deprecado: Grafana lo mantiene ahora en grafana-community.
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "grafana"
  version    = var.grafana_chart_version

  values = [yamlencode({
    # Sin `adminPassword`: el chart genera una aleatoria en el Secret `grafana`.
    persistence   = { enabled = false }
    testFramework = { enabled = false }

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }

    "grafana.ini" = {
      analytics = {
        reporting_enabled = false
        check_for_updates = false
      }
      users = { allow_sign_up = false }
    }

    datasources = {
      "datasources.yaml" = {
        apiVersion = 1
        datasources = [
          {
            name      = "Loki"
            uid       = "loki"
            type      = "loki"
            url       = local.loki_url
            access    = "proxy"
            isDefault = true
          },
          {
            name   = "Prometheus"
            uid    = "prometheus"
            type   = "prometheus"
            url    = var.prometheus_url
            access = "proxy"
          },
        ]
      }
    }

    dashboardProviders = {
      "dashboardproviders.yaml" = {
        apiVersion = 1
        providers = [{
          name            = "solventa"
          folder          = "Solventa"
          type            = "file"
          disableDeletion = true
          editable        = false
          options         = { path = "/var/lib/grafana/dashboards/solventa" }
        }]
      }
    }

    dashboards = {
      solventa = { for nombre, json in local.dashboards : nombre => { json = json } }
    }
  })]

  wait       = true
  depends_on = [helm_release.loki]
}
