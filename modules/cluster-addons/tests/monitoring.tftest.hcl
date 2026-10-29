# HA03 (ADR-0014 del backend): Prometheus mínimo y Prometheus Adapter para el HPA por solicitudes en curso.

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "kubectl" {}

variables {
  secret_store = { kind = "aws" }
}

run "prometheus_is_minimal_and_scrapes_only_annotated_pods" {
  command = plan

  assert {
    condition = alltrue([
      for c in ["alertmanager", "kube-state-metrics", "prometheus-node-exporter", "prometheus-pushgateway"] :
      yamldecode(helm_release.prometheus.values[0])[c].enabled == false
    ])
    error_message = "RULE monitoring-minimal: Prometheus must not install Alertmanager, kube-state-metrics, node-exporter or Pushgateway."
  }

  assert {
    condition     = yamldecode(helm_release.prometheus.values[0]).server.persistentVolume.enabled == false && yamldecode(helm_release.prometheus.values[0]).server.retention == "2h"
    error_message = "RULE monitoring-minimal: Prometheus keeps a short history without a persistent volume (nothing left behind on destroy)."
  }

  assert {
    condition = (
      !contains(keys(yamldecode(helm_release.prometheus.values[0]).scrapeConfigs), "kubernetes-pods")
      && alltrue([for job, cfg in yamldecode(helm_release.prometheus.values[0]).scrapeConfigs : cfg.enabled == false])
    )
    error_message = "RULE monitoring-minimal: only the chart's kubernetes-pods job (pods annotated with prometheus.io/scrape) stays enabled."
  }

  assert {
    condition     = helm_release.prometheus.version == "29.36.2" && helm_release.prometheus_adapter.version == "5.3.0"
    error_message = "Chart versions must be pinned."
  }
}

run "adapter_publishes_the_smoothed_concurrency_metric" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.prometheus_adapter.values[0]).rules.default == false && length(yamldecode(helm_release.prometheus_adapter.values[0]).rules.custom) == 1
    error_message = "RULE adapter: only the concurrency rule is published (no default rules)."
  }

  assert {
    condition = (
      yamldecode(helm_release.prometheus_adapter.values[0]).rules.custom[0].name.as == "http_requests_in_flight"
      && strcontains(yamldecode(helm_release.prometheus_adapter.values[0]).rules.custom[0].metricsQuery, "avg_over_time(<<.Series>>{<<.LabelMatchers>>}[30s])")
    )
    error_message = "RULE adapter: http_requests_in_flight must reach the HPA averaged over 30 s."
  }

  assert {
    condition     = yamldecode(helm_release.prometheus_adapter.values[0]).prometheus.url == "http://prometheus-server.monitoring.svc"
    error_message = "The adapter must query the in-cluster Prometheus."
  }
}
