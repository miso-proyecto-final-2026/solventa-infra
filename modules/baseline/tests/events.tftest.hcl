# HS2: el baseline crea los topics solo si la plataforma tiene el bus de eventos.

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

  service_db_secret_names    = { "solventa-backend" = "solventa/staging/solventa-backend/db" }
  service_db_secret_versions = { "solventa-backend" = "v1" }
}

run "without_events_there_is_no_topics_job" {
  command = plan

  assert {
    condition     = output.kafka_topics_job == null
    error_message = "Sin bus de eventos (kind o enable_events = false) no se crea el Job de topics."
  }
}

run "with_events_the_topics_job_runs_before_the_workloads" {
  command = plan

  variables {
    events = {
      bootstrap_servers = "b-1.eventos.abc.kafka.us-east-1.amazonaws.com:9098"
      region            = "us-east-1"
      topics = {
        "solventa.a.comandos" = { partitions = 3, retention_hours = 168, dlq = true }
      }
    }
  }

  assert {
    condition     = output.kafka_topics_job != null && can(regex("^kafka-topics-[0-9a-f]{10}$", output.kafka_topics_job))
    error_message = "Con bus de eventos se crea el Job de topics."
  }
}
