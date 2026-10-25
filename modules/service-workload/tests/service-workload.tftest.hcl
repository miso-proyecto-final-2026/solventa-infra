# T023: conjunto de objetos por servicio (data-model E7).

mock_provider "kubernetes" {}
mock_provider "kubectl" {}

variables {
  name = "solventa-backend"
  service = {
    image_tag   = "abc1234"
    port        = 8000
    health_path = "/health"
    resources = {
      requests = { cpu = "250m", memory = "256Mi" }
      limits   = { cpu = "1000m", memory = "512Mi" }
    }
    replicas          = { min = 2, max = 10 }
    autoscaling       = { cpu_target_percent = 70 }
    database_env_vars = ["DATABASE_URL", "COTIZACION_DATABASE_URL"]
    cache_env_var     = "REDIS_URL"
    settings          = { REGLAS_VERSION = "v1" }
    migration_command = ["alembic", "upgrade", "head"]
  }
  image_registry = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
  db_secret_name = "solventa/staging/solventa-backend/db"
  cache = {
    scheme     = "rediss"
    host       = "cache.example"
    secret_ref = "solventa/staging/cache"
  }
}

run "deployment_follows_the_workload_contract" {
  command = plan

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].name == "app"
    error_message = "The container must be named app (contract C3)."
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].replicas == "2"
    error_message = "RULE replicas: the Deployment must start at replicas.min (>= 2, FR-023)."
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].image == "123456789012.dkr.ecr.us-east-1.amazonaws.com/solventa-backend:abc1234"
    error_message = "The image must be <registry>/<service>:<image_tag>."
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].readiness_probe[0].http_get[0].path == "/health" && kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].liveness_probe[0].http_get[0].path == "/health"
    error_message = "Readiness and liveness probes must use health_path."
  }

  assert {
    condition     = alltrue([for c in kubernetes_deployment_v1.this.spec[0].template[0].spec[0].topology_spread_constraint : c.when_unsatisfiable == "ScheduleAnyway"])
    error_message = "RULE spread: topology spread must use ScheduleAnyway so the AZ drill can reschedule."
  }

  assert {
    condition     = kubernetes_service_v1.this.spec[0].type == "ClusterIP"
    error_message = "RULE no-loadbalancer: the Service must be ClusterIP, never LoadBalancer."
  }

  assert {
    condition     = kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].min_replicas == 2 && kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].max_replicas == 10
    error_message = "HPA min/max must come from replicas."
  }

  assert {
    condition     = length(kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].metric) == 1 && kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].metric[0].type == "Resource"
    error_message = "RULE hpa-metric: without concurrent_requests_target the HPA scales by CPU only."
  }

  assert {
    condition = (
      kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_up[0].stabilization_window_seconds == 30
      && length(kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_up[0].policy) == 1
      && kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_up[0].policy[0].type == "Pods"
      && kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_up[0].policy[0].value == 2
      && kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_up[0].policy[0].period_seconds == 60
    )
    error_message = "RULE scale-up: the default scale-up policy stays at 2 pods every 60 s after 30 s of stabilization."
  }

  assert {
    condition     = try(length(kubernetes_deployment_v1.this.spec[0].template[0].metadata[0].annotations), 0) == 0
    error_message = "RULE scrape: without metrics_path the pod must not carry scrape annotations."
  }

  assert {
    condition     = kubernetes_pod_disruption_budget_v1.this.spec[0].min_available == "1"
    error_message = "The PDB must keep minAvailable: 1."
  }

  assert {
    condition     = kubernetes_cron_job_v1.migrate[0].spec[0].suspend == true
    error_message = "The migration template CronJob must be suspended."
  }

  # Un pod de migración dentro del selector lo cuentan el HPA (métrica 0, sin request de CPU) y el PDB (HA03).
  assert {
    condition = !alltrue([
      for k, v in kubernetes_deployment_v1.this.spec[0].selector[0].match_labels :
      lookup(kubernetes_job_v1.migrate[0].spec[0].template[0].metadata[0].labels, k, null) == v
    ])
    error_message = "RULE migration-labels: the migration Job pods must not match the Deployment selector (HPA, PDB)."
  }

  assert {
    condition = !alltrue([
      for k, v in kubernetes_deployment_v1.this.spec[0].selector[0].match_labels :
      lookup(kubernetes_cron_job_v1.migrate[0].spec[0].job_template[0].spec[0].template[0].metadata[0].labels, k, null) == v
    ])
    error_message = "RULE migration-labels: the CI migration pods (from the CronJob) must not match the Deployment selector."
  }

  assert {
    condition     = kubernetes_service_account_v1.this.automount_service_account_token == false
    error_message = "The ServiceAccount must not automount its token."
  }
}

run "connection_secret_has_the_contract_formats" {
  command = plan

  assert {
    condition     = strcontains(yamldecode(kubectl_manifest.connection.yaml_body).spec.target.template.data["DATABASE_URL"], "postgresql+psycopg://{{ .db_username }}:{{ .db_password }}@{{ .db_host }}:{{ .db_port }}/{{ .db_dbname }}?sslmode=require")
    error_message = "RULE connection: DATABASE_URL must use postgresql+psycopg with sslmode=require (contract C2)."
  }

  assert {
    condition     = yamldecode(kubectl_manifest.connection.yaml_body).spec.target.template.data["COTIZACION_DATABASE_URL"] == yamldecode(kubectl_manifest.connection.yaml_body).spec.target.template.data["DATABASE_URL"]
    error_message = "Every name in database_env_vars must receive the DB URL."
  }

  assert {
    condition     = yamldecode(kubectl_manifest.connection.yaml_body).spec.target.template.data["REDIS_URL"] == "rediss://:{{ .cache_auth_token }}@{{ .cache_host }}:{{ .cache_port }}/0"
    error_message = "RULE connection: REDIS_URL must use rediss with the auth token (contract C2)."
  }

  assert {
    condition     = !can(regex("password[\"']?\\s*:\\s*\"[A-Za-z0-9]{16,}\"", kubectl_manifest.connection.yaml_body))
    error_message = "RULE secrets: the ExternalSecret must hold references only, never values."
  }
}

run "kind_formats_omit_tls_and_token" {
  command = plan

  variables {
    image_registry = ""
    db_sslmode     = "disable"
    cache = {
      scheme = "redis"
      host   = "redis.local-deps.svc"
    }
  }

  assert {
    condition     = yamldecode(kubectl_manifest.connection.yaml_body).spec.target.template.data["DATABASE_URL"] == "postgresql+psycopg://{{ .db_username }}:{{ .db_password }}@{{ .db_host }}:{{ .db_port }}/{{ .db_dbname }}"
    error_message = "kind DATABASE_URL must not carry sslmode (contract C2)."
  }

  assert {
    condition     = yamldecode(kubectl_manifest.connection.yaml_body).spec.target.template.data["REDIS_URL"] == "redis://redis.local-deps.svc:6379/0"
    error_message = "kind REDIS_URL must be redis://redis.local-deps.svc:6379/0."
  }

  assert {
    condition     = kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].image == "solventa-backend:abc1234"
    error_message = "Without registry the image must be <service>:<tag>."
  }
}

run "service_without_migration_or_cache" {
  command = plan

  variables {
    service = {
      image_tag   = "abc1234"
      port        = 8000
      health_path = "/health"
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "256Mi" }
      }
      replicas          = { min = 2, max = 4 }
      migration_command = null
      cache_env_var     = null
    }
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.migrate) == 0 && length(kubernetes_job_v1.migrate) == 0
    error_message = "A null migration_command must not create the migration CronJob or Job."
  }

  assert {
    condition     = !contains(keys(yamldecode(kubectl_manifest.connection.yaml_body).spec.target.template.data), "REDIS_URL")
    error_message = "A null cache_env_var must not generate a cache URL."
  }
}

run "shared_secret_is_injected_from_the_secret_store" {
  command = plan

  variables {
    name = "solventa-identidad"
    service = {
      image_tag   = "abc1234"
      port        = 8000
      health_path = "/health"
      resources = {
        requests = { cpu = "250m", memory = "256Mi" }
        limits   = { cpu = "1000m", memory = "512Mi" }
      }
      replicas          = { min = 2, max = 6 }
      database_env_vars = ["DATABASE_URL"]
      cache_env_var     = null
      secret_env_vars   = { SERVICE_API_KEYS = "solventa/staging/identidad-service-key" }
      migration_command = ["alembic", "upgrade", "head"]
    }
    db_secret_name = "solventa/staging/solventa-identidad/db"
  }

  assert {
    condition     = yamldecode(kubectl_manifest.connection.yaml_body).spec.target.template.data["SERVICE_API_KEYS"] == "{{ .shared_service_api_keys }}"
    error_message = "The shared secret must be exposed as the declared env var through the ExternalSecret template."
  }

  assert {
    condition     = contains([for d in yamldecode(kubectl_manifest.connection.yaml_body).spec.data : d.remoteRef.key if d.secretKey == "shared_service_api_keys"], "solventa/staging/identidad-service-key") && contains([for d in yamldecode(kubectl_manifest.connection.yaml_body).spec.data : d.remoteRef.property if d.secretKey == "shared_service_api_keys"], "value")
    error_message = "The ExternalSecret must read property `value` of the shared secret."
  }

  assert {
    condition     = !can(regex("[A-Za-z0-9]{40,}", kubectl_manifest.connection.yaml_body))
    error_message = "RULE no-secrets-in-state: the manifest must hold references, never secret values."
  }
}

run "exposed_service_gets_a_fixed_node_port_and_internal_service_does_not" {
  command = plan

  variables {
    service = {
      image_tag   = "abc1234"
      port        = 8000
      health_path = "/health"
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "256Mi" }
      }
      replicas = { min = 2, max = 4 }
      edge     = { node_port = 30080, path_prefixes = ["/v1/cotizaciones"] }
    }
  }

  assert {
    condition     = length(kubernetes_service_v1.edge) == 1 && kubernetes_service_v1.edge[0].spec[0].type == "NodePort" && kubernetes_service_v1.edge[0].spec[0].port[0].node_port == 30080
    error_message = "RULE edge-nodeport: an exposed service needs a NodePort Service on its fixed port."
  }

  assert {
    condition     = kubernetes_service_v1.this.spec[0].type == "ClusterIP"
    error_message = "RULE no-loadbalancer: the main Service stays ClusterIP; the cluster never creates load balancers."
  }
}

run "service_without_edge_has_no_node_port" {
  command = plan

  assert {
    condition     = length(kubernetes_service_v1.edge) == 0
    error_message = "RULE edge-optional: a service without edge must not get a NodePort Service."
  }
}

run "concurrency_target_scales_by_requests_in_flight" {
  command = plan

  variables {
    service = {
      image_tag   = "abc1234"
      port        = 8000
      health_path = "/health"
      resources = {
        requests = { cpu = "250m", memory = "256Mi" }
        limits   = { cpu = "1000m", memory = "512Mi" }
      }
      replicas = { min = 2, max = 10 }
      autoscaling = {
        cpu_target_percent         = 70
        concurrent_requests_target = 3
        scale_up                   = { pods = 4, percent = 100, period_seconds = 15, stabilization_window_seconds = 0 }
      }
      metrics_path      = "/metrics"
      database_env_vars = ["DATABASE_URL"]
      cache_env_var     = "REDIS_URL"
      migration_command = ["alembic", "upgrade", "head"]
      edge              = { node_port = 30080, path_prefixes = ["/v1/cotizaciones"] }
    }
  }

  assert {
    condition = anytrue([
      for m in kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].metric :
      m.type == "Pods" && m.pods[0].metric[0].name == "http_requests_in_flight" && m.pods[0].target[0].type == "AverageValue" && m.pods[0].target[0].average_value == "3"
    ])
    error_message = "RULE hpa-metric: with concurrent_requests_target the HPA must scale by http_requests_in_flight (AverageValue per pod)."
  }

  assert {
    condition = anytrue([
      for m in kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].metric :
      m.type == "Resource" && m.resource[0].name == "cpu" && m.resource[0].target[0].average_utilization == 70
    ])
    error_message = "RULE hpa-metric: CPU must stay as the fallback metric."
  }

  assert {
    condition = (
      kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_up[0].stabilization_window_seconds == 0
      && kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_up[0].select_policy == "Max"
      && anytrue([for p in kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_up[0].policy : p.type == "Pods" && p.value == 4 && p.period_seconds == 15])
      && anytrue([for p in kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_up[0].policy : p.type == "Percent" && p.value == 100 && p.period_seconds == 15])
    )
    error_message = "RULE scale-up: the service's scale_up policy (Pods and Percent, Max) must reach the HPA."
  }

  assert {
    condition = (
      kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_down[0].stabilization_window_seconds == 300
      && kubernetes_horizontal_pod_autoscaler_v2.this.spec[0].behavior[0].scale_down[0].policy[0].value == 1
    )
    error_message = "Scale-down stays conservative (1 pod every 60 s after 300 s) for every service."
  }

  assert {
    condition = kubernetes_deployment_v1.this.spec[0].template[0].metadata[0].annotations == tomap({
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "8000"
      "prometheus.io/path"   = "/metrics"
    })
    error_message = "RULE scrape: with metrics_path the pod must be annotated for Prometheus (scrape, port, path)."
  }

  assert {
    condition     = kubernetes_service_v1.edge[0].spec[0].type == "NodePort" && length(kubernetes_service_v1.edge[0].spec[0].port) == 1 && kubernetes_service_v1.edge[0].spec[0].port[0].target_port == "http"
    error_message = "RULE edge: the edge NodePort only exposes the http port; the metrics path is filtered by the API Gateway routes."
  }
}
