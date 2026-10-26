resource "kubernetes_namespace_v1" "staging" {
  metadata {
    name = var.staging_namespace

    labels = {
      "app.kubernetes.io/part-of" = "solventa"
    }
  }
}

resource "kubernetes_namespace_v1" "system" {
  metadata {
    name = var.system_namespace

    labels = {
      "app.kubernetes.io/part-of" = "solventa"
    }
  }
}

# FR-009: métricas para el HPA.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  values = [yamlencode({
    args = var.metrics_server_args
  })]

  wait = true
}

# External Secrets Operator: entrega las credenciales sin pasar por el estado de Terraform (research R9).
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = var.eso_namespace
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      name = "external-secrets"
    }
  })]

  wait = true
}

# HA03 (ADR-0015 del backend): solicitudes en curso por pod para el HPA. Prometheus mínimo, solo recoge los pods
# anotados con prometheus.io/scrape (lo pone service-workload cuando el servicio declara metrics_path); sin
# Alertmanager, exportadores ni volumen persistente: la historia corta basta para el HPA y se pierde al reiniciar.
resource "helm_release" "prometheus" {
  name             = "prometheus"
  namespace        = var.monitoring_namespace
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = var.prometheus_chart_version

  values = [yamlencode({
    alertmanager               = { enabled = false }
    "kube-state-metrics"       = { enabled = false }
    "prometheus-node-exporter" = { enabled = false }
    "prometheus-pushgateway"   = { enabled = false }

    server = {
      retention        = "2h"
      persistentVolume = { enabled = false }
      global = {
        scrape_interval     = var.metrics_scrape_interval
        scrape_timeout      = "5s"
        evaluation_interval = "1m"
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }

    # Solo el trabajo de pods anotados; los demás del chart (nodos, cAdvisor, API server...) no los usa el HPA.
    scrapeConfigs = { for job in local.unused_scrape_jobs : job => { enabled = false } }
  })]

  wait = true
}

# Publica la serie en custom.metrics.k8s.io, promediada en una ventana para que el HPA no oscile con valores bajos.
resource "helm_release" "prometheus_adapter" {
  name       = "prometheus-adapter"
  namespace  = var.monitoring_namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-adapter"
  version    = var.prometheus_adapter_chart_version

  values = [yamlencode({
    prometheus = {
      url  = "http://prometheus-server.${var.monitoring_namespace}.svc"
      port = 80
    }

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }

    rules = {
      default = false
      custom = [{
        seriesQuery = "${local.concurrency_metric}{namespace!=\"\",pod!=\"\"}"
        resources = {
          overrides = {
            namespace = { resource = "namespace" }
            pod       = { resource = "pod" }
          }
        }
        name         = { matches = "^${local.concurrency_metric}$", as = local.concurrency_metric }
        metricsQuery = "sum(avg_over_time(<<.Series>>{<<.LabelMatchers>>}[${var.concurrency_window}])) by (<<.GroupBy>>)"
      }]
    }
  })]

  wait       = true
  depends_on = [helm_release.prometheus]
}

locals {
  concurrency_metric = "http_requests_in_flight"

  unused_scrape_jobs = [
    "prometheus", "kubernetes-api-servers", "kubernetes-nodes", "kubernetes-nodes-cadvisor",
    "kubernetes-service-endpoints", "kubernetes-service-endpoints-slow", "prometheus-pushgateway",
    "kubernetes-services", "kubernetes-pods-slow",
  ]
}
