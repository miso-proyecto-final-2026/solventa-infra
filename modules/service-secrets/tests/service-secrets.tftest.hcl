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
