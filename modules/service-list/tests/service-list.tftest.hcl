# T008: un caso válido y un caso inválido por cada regla V1–V7 (contrato C1).

variables {
  config = {
    reserved_schemas = ["identidad", "pagos"]
    drop_schemas     = []
    services = [
      {
        name        = "solventa-backend"
        image_tag   = "abc1234"
        port        = 8000
        health_path = "/health"
        resources = {
          requests = { cpu = "250m", memory = "256Mi" }
          limits   = { cpu = "1000m", memory = "512Mi" }
        }
        replicas          = { min = 2, max = 10 }
        owned_schemas     = ["public", "cotizacion"]
        database_env_vars = ["DATABASE_URL", "COTIZACION_DATABASE_URL"]
        settings          = { REGLAS_VERSION = "v1" }
      },
    ]
  }
}

run "valid_config_passes" {
  command = plan

  assert {
    condition     = output.services["solventa-backend"].role_name == "solventa_backend"
    error_message = "role_name must replace '-' with '_'."
  }

  assert {
    condition     = output.schema_owner["cotizacion"] == "solventa-backend"
    error_message = "schema_owner must map each owned schema to its service."
  }

  assert {
    condition     = output.services["solventa-backend"].deploy_repository == "miso-proyecto-final-2026/solventa-backend"
    error_message = "deploy_repository must default to miso-proyecto-final-2026/<name>."
  }
}

run "v1_invalid_name" {
  command = plan

  variables {
    config = {
      services = [{
        name        = "Bad_Name"
        image_tag   = "x"
        port        = 80
        health_path = "/h"
        resources = {
          requests = { cpu = "1m", memory = "1Mi" }
          limits   = { cpu = "1m", memory = "1Mi" }
        }
        replicas = { min = 2, max = 2 }
      }]
    }
  }

  expect_failures = [var.config]
}

run "v1_duplicate_name" {
  command = plan

  variables {
    config = {
      services = [
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/h"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
        },
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/h"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
        },
      ]
    }
  }

  expect_failures = [var.config]
}

run "v2_two_owners_same_schema" {
  command = plan

  variables {
    config = {
      services = [
        {
          name          = "svc-a"
          image_tag     = "x"
          port          = 80
          health_path   = "/h"
          owned_schemas = ["cotizacion"]
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
        },
        {
          name          = "svc-b"
          image_tag     = "x"
          port          = 80
          health_path   = "/h"
          owned_schemas = ["cotizacion"]
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
        },
      ]
    }
  }

  expect_failures = [var.config]
}

run "v3_reserved_and_owned" {
  command = plan

  variables {
    config = {
      reserved_schemas = ["pagos"]
      services = [{
        name          = "svc-a"
        image_tag     = "x"
        port          = 80
        health_path   = "/h"
        owned_schemas = ["pagos"]
        resources = {
          requests = { cpu = "1m", memory = "1Mi" }
          limits   = { cpu = "1m", memory = "1Mi" }
        }
        replicas = { min = 2, max = 2 }
      }]
    }
  }

  expect_failures = [var.config]
}

run "v4_drop_owned_schema" {
  command = plan

  variables {
    config = {
      drop_schemas = ["cotizacion"]
      services = [{
        name          = "svc-a"
        image_tag     = "x"
        port          = 80
        health_path   = "/h"
        owned_schemas = ["cotizacion"]
        resources = {
          requests = { cpu = "1m", memory = "1Mi" }
          limits   = { cpu = "1m", memory = "1Mi" }
        }
        replicas = { min = 2, max = 2 }
      }]
    }
  }

  expect_failures = [var.config]
}

run "v5_replicas_min_below_two" {
  command = plan

  variables {
    config = {
      services = [{
        name        = "svc-a"
        image_tag   = "x"
        port        = 80
        health_path = "/h"
        resources = {
          requests = { cpu = "1m", memory = "1Mi" }
          limits   = { cpu = "1m", memory = "1Mi" }
        }
        replicas = { min = 1, max = 3 }
      }]
    }
  }

  expect_failures = [var.config]
}

run "v6_settings_collide_with_connection_var" {
  command = plan

  variables {
    config = {
      services = [{
        name        = "svc-a"
        image_tag   = "x"
        port        = 80
        health_path = "/h"
        settings    = { DATABASE_URL = "x" }
        resources = {
          requests = { cpu = "1m", memory = "1Mi" }
          limits   = { cpu = "1m", memory = "1Mi" }
        }
        replicas = { min = 2, max = 2 }
      }]
    }
  }

  expect_failures = [var.config]
}

run "v7_invalid_health_path" {
  command = plan

  variables {
    config = {
      services = [{
        name        = "svc-a"
        image_tag   = "x"
        port        = 80
        health_path = "health"
        resources = {
          requests = { cpu = "1m", memory = "1Mi" }
          limits   = { cpu = "1m", memory = "1Mi" }
        }
        replicas = { min = 2, max = 2 }
      }]
    }
  }

  expect_failures = [var.config]
}
