# T047 (SC-004): añadir un servicio solo crea objetos nuevos; los del servicio existente no cambian.
# El Job db-access se excluye explícitamente: se reemplaza por diseño al cambiar el hash (plan, tabla de riesgos).

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "kubectl" {}

variables {
  secret_store = { kind = "aws" }
  db = {
    host             = "postgres.example"
    admin_secret_ref = "rds!db-admin"
  }
  cache = {
    scheme     = "rediss"
    host       = "cache.example"
    secret_ref = "solventa/staging/cache"
  }
  image_registry   = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
  reserved_schemas = ["pagos"]

  services = {
    "solventa-backend" = {
      image_tag   = "abc1234"
      port        = 8000
      health_path = "/health"
      resources = {
        requests = { cpu = "250m", memory = "256Mi" }
        limits   = { cpu = "1000m", memory = "512Mi" }
      }
      replicas          = { min = 2, max = 10 }
      owned_schemas     = ["public", "cotizacion"]
      database_env_vars = ["DATABASE_URL"]
      cache_env_var     = "REDIS_URL"
      migration_command = ["alembic", "upgrade", "head"]
      role_name         = "solventa_backend"
    }
  }

  service_db_secret_names = {
    "solventa-backend" = "solventa/staging/solventa-backend/db"
  }
  service_db_secret_versions = {
    "solventa-backend" = "v1"
  }
}

run "initial_state" {
  command = apply

  assert {
    condition     = output.deployments["solventa-backend"] == "solventa-backend"
    error_message = "The initial apply must create the backend Deployment."
  }
}

run "add_a_service" {
  command = plan

  variables {
    services = {
      "solventa-backend" = {
        image_tag   = "abc1234"
        port        = 8000
        health_path = "/health"
        resources = {
          requests = { cpu = "250m", memory = "256Mi" }
          limits   = { cpu = "1000m", memory = "512Mi" }
        }
        replicas          = { min = 2, max = 10 }
        owned_schemas     = ["public", "cotizacion"]
        database_env_vars = ["DATABASE_URL"]
        cache_env_var     = "REDIS_URL"
        migration_command = ["alembic", "upgrade", "head"]
        role_name         = "solventa_backend"
      }
      "ms-prueba" = {
        image_tag   = "abc1234"
        port        = 8000
        health_path = "/health"
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }
        replicas      = { min = 2, max = 4 }
        owned_schemas = ["identidad"]
        role_name     = "ms_prueba"
      }
    }
    service_db_secret_names = {
      "solventa-backend" = "solventa/staging/solventa-backend/db"
      "ms-prueba"        = "solventa/staging/ms-prueba/db"
    }
    service_db_secret_versions = {
      "solventa-backend" = "v1"
      "ms-prueba"        = "v1"
    }
  }

  assert {
    condition     = output.migration_jobs["solventa-backend"] == run.initial_state.migration_jobs["solventa-backend"]
    error_message = "RULE additions-only: the existing service's migration Job must not be replaced."
  }

  assert {
    condition     = output.deployments["solventa-backend"] == run.initial_state.deployments["solventa-backend"] && contains(keys(output.deployments), "ms-prueba")
    error_message = "RULE additions-only: the new service must be added without touching the existing one."
  }

  assert {
    condition     = output.db_access_job != run.initial_state.db_access_job
    error_message = "The db-access Job is expected to be replaced (new hash) when the service list changes."
  }
}

# La observabilidad (Grafana, Loki, Alloy) es opcional y no se instala si no se pide.
run "observability_is_off_by_default" {
  command = plan

  assert {
    condition     = length(module.observability) == 0
    error_message = "RULE observability-optional: without enable_observability nothing is installed."
  }
}

run "observability_collects_workload_and_platform_logs_when_enabled" {
  command = plan

  variables {
    enable_observability = true
  }

  assert {
    condition     = length(module.observability) == 1 && module.observability[0].grafana_namespace == "monitoring"
    error_message = "RULE observability-optional: enable_observability installs Grafana next to Prometheus."
  }
}
