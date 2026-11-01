# Logs y métricas en Grafana con la menor infraestructura posible: Loki sin volúmenes, un solo Alloy, Grafana sin estado.

mock_provider "helm" {}

run "loki_is_single_binary_without_volumes" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.loki.values[0]).deploymentMode == "SingleBinary" && yamldecode(helm_release.loki.values[0]).singleBinary.replicas == 1
    error_message = "RULE observability-minimal: Loki runs as one single-binary pod."
  }

  assert {
    condition     = yamldecode(helm_release.loki.values[0]).singleBinary.persistence.enabled == false && yamldecode(helm_release.loki.values[0]).loki.storage.type == "filesystem"
    error_message = "RULE observability-minimal: Loki uses no PVC and no bucket (nothing left behind on destroy)."
  }

  assert {
    condition     = yamldecode(helm_release.loki.values[0]).singleBinary.extraVolumes[0].emptyDir.sizeLimit == "3Gi"
    error_message = "RULE observability-minimal: Loki's ephemeral disk is capped so it cannot evict the node."
  }

  assert {
    condition = alltrue([
      for c in ["read", "write", "backend"] : yamldecode(helm_release.loki.values[0])[c].replicas == 0
    ])
    error_message = "RULE observability-minimal: the scalable-mode components stay off."
  }

  assert {
    condition = alltrue([
      for c in ["gateway", "chunksCache", "resultsCache", "lokiCanary", "test"] : yamldecode(helm_release.loki.values[0])[c].enabled == false
    ])
    error_message = "RULE observability-minimal: no gateway, caches, canary or test pods."
  }

  assert {
    condition     = yamldecode(helm_release.loki.values[0]).loki.limits_config.retention_period == "48h" && yamldecode(helm_release.loki.values[0]).loki.compactor.retention_enabled == true
    error_message = "RULE observability-retention: logs are kept 48 h and the compactor enforces it."
  }
}

run "alloy_is_one_pod_reading_logs_through_the_api" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.alloy.values[0]).controller.type == "deployment" && yamldecode(helm_release.alloy.values[0]).controller.replicas == 1
    error_message = "RULE observability-minimal: Alloy is a single Deployment, not a DaemonSet per node."
  }

  assert {
    condition     = strcontains(yamldecode(helm_release.alloy.values[0]).alloy.configMap.content, "loki.source.kubernetes") && !strcontains(yamldecode(helm_release.alloy.values[0]).alloy.configMap.content, "loki.source.file")
    error_message = "RULE observability-minimal: logs are read through the Kubernetes API, with no host path mounts."
  }

  assert {
    condition     = strcontains(yamldecode(helm_release.alloy.values[0]).alloy.configMap.content, "http://loki.monitoring.svc:3100/loki/api/v1/push")
    error_message = "Alloy must push to the in-cluster Loki."
  }

  assert {
    condition     = strcontains(yamldecode(helm_release.alloy.values[0]).alloy.configMap.content, "\"staging\"")
    error_message = "Alloy collects the workload namespace by default."
  }
}

run "alloy_keeps_labels_low_cardinality" {
  command = plan

  assert {
    condition = (
      !strcontains(yamldecode(helm_release.alloy.values[0]).alloy.configMap.content, "target_label  = \"trace_id\"")
      && !strcontains(yamldecode(helm_release.alloy.values[0]).alloy.configMap.content, "target_label  = \"correlation_id\"")
      && strcontains(yamldecode(helm_release.alloy.values[0]).alloy.configMap.content, "level = \"\"")
    )
    error_message = "RULE observability-cardinality: only namespace, service, pod, container and level are labels; trace ids stay in the log line."
  }
}

run "extra_namespaces_are_collected" {
  command = plan

  variables {
    log_namespaces = ["staging", "platform"]
  }

  assert {
    condition     = strcontains(yamldecode(helm_release.alloy.values[0]).alloy.configMap.content, "[\"staging\",\"platform\"]")
    error_message = "log_namespaces must reach the Alloy configuration."
  }
}

run "grafana_is_stateless_private_and_provisioned" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.grafana.values[0]).persistence.enabled == false
    error_message = "RULE observability-minimal: Grafana has no persistent volume."
  }

  assert {
    condition     = !contains(keys(yamldecode(helm_release.grafana.values[0])), "adminPassword") && !contains(keys(yamldecode(helm_release.grafana.values[0])), "ingress") && !contains(keys(yamldecode(helm_release.grafana.values[0])), "service")
    error_message = "RULE observability-private: no admin password in state, no Ingress and no public Service (access is by port-forward)."
  }

  assert {
    condition = (
      [for d in yamldecode(helm_release.grafana.values[0]).datasources["datasources.yaml"].datasources : d.uid] == ["loki", "prometheus"]
      && yamldecode(helm_release.grafana.values[0]).datasources["datasources.yaml"].datasources[1].url == "http://prometheus-server.monitoring.svc"
    )
    error_message = "Grafana must provision the Loki and Prometheus data sources."
  }

  assert {
    condition     = length(yamldecode(helm_release.grafana.values[0]).dashboards.solventa) == 2
    error_message = "Both dashboards (logs and services) are provisioned."
  }
}

run "dashboards_are_valid_and_use_the_provisioned_datasources" {
  command = plan

  assert {
    condition = alltrue([
      for nombre, d in local.dashboards : (
        can(jsondecode(d).uid) && length(jsondecode(d).panels) > 0 && jsondecode(d).editable == false
      )
    ])
    error_message = "Each dashboard must be valid JSON with a uid, panels and read-only."
  }

  assert {
    condition = alltrue([
      for nombre, d in local.dashboards : alltrue([
        for p in jsondecode(d).panels : contains(["loki", "prometheus"], p.datasource.uid)
      ])
    ])
    error_message = "Panels may only use the provisioned data sources (uid loki / prometheus)."
  }
}

run "chart_versions_are_pinned" {
  command = plan

  assert {
    condition     = helm_release.grafana.version == "13.6.0" && helm_release.loki.version == "7.3.0" && helm_release.alloy.version == "1.13.1"
    error_message = "Chart versions must be pinned."
  }
}

# Con bucket de logs Loki guarda en S3 (Pod Identity, sin claves) y conserva más tiempo; el WAL sigue en el disco efímero.
run "loki_uses_s3_when_a_logs_bucket_is_given" {
  command = plan

  variables {
    logs_bucket        = "solventa-staging-logs-123456789012"
    logs_bucket_region = "us-east-1"
  }

  assert {
    condition = (
      yamldecode(helm_release.loki.values[0]).loki.storage.type == "s3" &&
      yamldecode(helm_release.loki.values[0]).loki.storage.bucketNames.chunks == "solventa-staging-logs-123456789012" &&
      yamldecode(helm_release.loki.values[0]).loki.storage.s3.region == "us-east-1"
    )
    error_message = "RULE logs-s3: Loki stores chunks and index in the logs bucket."
  }

  assert {
    condition = (
      yamldecode(helm_release.loki.values[0]).loki.schemaConfig.configs[0].object_store == "s3" &&
      yamldecode(helm_release.loki.values[0]).loki.compactor.delete_request_store == "s3"
    )
    error_message = "RULE logs-s3: the index schema and the compactor use the same object store."
  }

  assert {
    condition     = !can(yamldecode(helm_release.loki.values[0]).loki.storage.s3.accessKeyId) && !can(yamldecode(helm_release.loki.values[0]).loki.storage.s3.secretAccessKey)
    error_message = "RULE logs-s3: no static AWS keys; credentials come from Pod Identity."
  }

  assert {
    condition     = yamldecode(helm_release.loki.values[0]).serviceAccount.name == "loki"
    error_message = "RULE logs-s3: Loki runs with the service account the Pod Identity role is bound to."
  }

  assert {
    condition     = yamldecode(helm_release.loki.values[0]).loki.limits_config.retention_period == "168h"
    error_message = "RULE logs-s3: with a bucket logs are kept 7 days."
  }

  assert {
    condition     = yamldecode(helm_release.loki.values[0]).singleBinary.persistence.enabled == false && yamldecode(helm_release.loki.values[0]).singleBinary.extraVolumes[0].emptyDir.sizeLimit == "3Gi"
    error_message = "RULE observability-minimal: still no PVC; the ephemeral disk holds only the WAL and index cache."
  }
}

run "an_explicit_retention_overrides_the_default" {
  command = plan

  variables {
    logs_bucket        = "solventa-staging-logs-123456789012"
    logs_bucket_region = "us-east-1"
    log_retention      = "72h"
  }

  assert {
    condition     = yamldecode(helm_release.loki.values[0]).loki.limits_config.retention_period == "72h"
    error_message = "log_retention must win over the default."
  }
}

run "a_bucket_without_region_is_rejected" {
  command = plan

  variables {
    logs_bucket = "solventa-staging-logs-123456789012"
  }

  expect_failures = [var.logs_bucket_region]
}
