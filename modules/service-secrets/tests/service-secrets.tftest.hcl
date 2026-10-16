# T021: contraseñas alfanuméricas de 32 caracteres, sin ventana de recuperación y nombres del contrato.

mock_provider "aws" {}
mock_provider "random" {}

variables {
  services = {
    "solventa-backend" = { role_name = "solventa_backend" }
    "ms-prueba"        = { role_name = "ms_prueba" }
  }
  db_host          = "solventa-staging-postgres.abc.us-east-1.rds.amazonaws.com"
  cache_host       = "solventa-staging-cache.abc.cache.amazonaws.com"
  cache_auth_token = "tokentokentokentokentokentoken12"
  tags = {
    Project     = "solventa"
    Environment = "staging"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "platform"
  }
}

run "secrets_follow_the_contract" {
  command = plan

  assert {
    condition     = alltrue([for k, p in random_password.service_db : p.length == 32 && p.special == false])
    error_message = "RULE secrets-format: passwords must be 32 alphanumeric characters."
  }

  assert {
    condition     = alltrue([for s in concat(values(aws_secretsmanager_secret.service_db), [aws_secretsmanager_secret.cache]) : s.recovery_window_in_days == 0])
    error_message = "RULE secrets-teardown: recovery_window_in_days must be 0."
  }

  assert {
    condition     = aws_secretsmanager_secret.service_db["solventa-backend"].name == "solventa/staging/solventa-backend/db"
    error_message = "DB secret name must be solventa/staging/<service>/db."
  }

  assert {
    condition     = aws_secretsmanager_secret.cache.name == "solventa/staging/cache"
    error_message = "Cache secret name must be solventa/staging/cache."
  }

  assert {
    condition     = alltrue([for s in concat(values(aws_secretsmanager_secret.service_db), [aws_secretsmanager_secret.cache]) : alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(s.tags), k)])])
    error_message = "RULE tags: every resource must carry the five mandatory tags."
  }
}

run "shared_secrets_follow_the_contract" {
  command = plan

  variables {
    shared_secret_names = ["solventa/staging/identidad-service-key"]
  }

  assert {
    condition     = aws_secretsmanager_secret.shared["solventa/staging/identidad-service-key"].name == "solventa/staging/identidad-service-key" && aws_secretsmanager_secret.shared["solventa/staging/identidad-service-key"].recovery_window_in_days == 0
    error_message = "Shared secrets must use the given full name and recovery_window_in_days = 0."
  }

  assert {
    condition     = alltrue([for k, p in random_password.shared : p.length >= 32 && p.special == false])
    error_message = "Shared secrets must be at least 32 alphanumeric characters."
  }

  assert {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(aws_secretsmanager_secret.shared["solventa/staging/identidad-service-key"].tags), k)])
    error_message = "RULE tags: shared secrets must carry the five mandatory tags."
  }
}

run "no_shared_secrets_by_default" {
  command = plan

  assert {
    condition     = length(aws_secretsmanager_secret.shared) == 0
    error_message = "Without shared_secret_names no extra secret must be created."
  }
}
