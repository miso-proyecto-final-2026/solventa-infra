# T053 (SC-008): tras un rollout de CI, un plan no propone cambiar la imagen del Deployment ni de la plantilla.

mock_provider "kubernetes" {}
mock_provider "kubectl" {}

variables {
  name = "solventa-backend"
  service = {
    image_tag   = "aaaaaaa"
    port        = 8000
    health_path = "/health"
    resources = {
      requests = { cpu = "250m", memory = "256Mi" }
      limits   = { cpu = "1000m", memory = "512Mi" }
    }
    replicas          = { min = 2, max = 10 }
    migration_command = ["alembic", "upgrade", "head"]
    cache_env_var     = "REDIS_URL"
  }
  image_registry = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
  db_secret_name = "solventa/staging/solventa-backend/db"
  cache = {
    scheme     = "rediss"
    host       = "cache.example"
    secret_ref = "solventa/staging/cache"
  }
}

run "first_deploy" {
  command = apply

  assert {
    condition     = endswith(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].image, ":aaaaaaa")
    error_message = "The first apply must deploy the initial image tag."
  }
}

run "plan_after_ci_rolled_out_a_new_image" {
  command = plan

  variables {
    service = {
      image_tag   = "bbbbbbb"
      port        = 8000
      health_path = "/health"
      resources = {
        requests = { cpu = "250m", memory = "256Mi" }
        limits   = { cpu = "1000m", memory = "512Mi" }
      }
      replicas          = { min = 2, max = 10 }
      migration_command = ["alembic", "upgrade", "head"]
      cache_env_var     = "REDIS_URL"
    }
  }

  assert {
    condition     = endswith(kubernetes_deployment_v1.this.spec[0].template[0].spec[0].container[0].image, ":aaaaaaa")
    error_message = "RULE ignore-changes: the Deployment image must stay as rolled out by CI (SC-008)."
  }

  assert {
    condition     = endswith(kubernetes_cron_job_v1.migrate[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].image, ":aaaaaaa")
    error_message = "RULE ignore-changes: the migration template image must stay as set by CI (SC-008)."
  }
}
