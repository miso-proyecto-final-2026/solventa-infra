# T008: un caso válido y un caso inválido por cada regla V1–V14 (contrato C1).

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

run "v8_secret_env_vars_are_collected_and_validated" {
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
          replicas        = { min = 2, max = 2 }
          secret_env_vars = { SERVICE_API_KEYS = "solventa/staging/identidad-service-key" }
        },
        {
          name        = "svc-b"
          image_tag   = "x"
          port        = 80
          health_path = "/h"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas        = { min = 2, max = 2 }
          secret_env_vars = { IDENTIDAD_SERVICE_KEY = "solventa/staging/identidad-service-key" }
        },
      ]
    }
  }

  assert {
    condition     = output.shared_secret_names == toset(["solventa/staging/identidad-service-key"])
    error_message = "A secret shared by two services must be listed once."
  }
}

run "v8_secret_name_outside_the_prefix" {
  command = plan

  variables {
    config = {
      services = [{
        name            = "svc-a"
        image_tag       = "x"
        port            = 80
        health_path     = "/h"
        secret_env_vars = { SERVICE_API_KEYS = "otro-prefijo/clave" }
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

run "v8_secret_env_var_collides_with_a_setting" {
  command = plan

  variables {
    config = {
      services = [{
        name            = "svc-a"
        image_tag       = "x"
        port            = 80
        health_path     = "/h"
        settings        = { SERVICE_API_KEYS = "x" }
        secret_env_vars = { SERVICE_API_KEYS = "solventa/staging/k" }
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

run "v9_edge_valid_and_optional" {
  command = plan

  variables {
    config = {
      services = [
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = { node_port = 30080, path_prefixes = ["/v1/a"] }
        },
        {
          name        = "svc-b"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = null
        },
      ]
    }
  }

  assert {
    condition     = output.services["svc-a"].edge.node_port == 30080 && output.services["svc-b"].edge == null
    error_message = "RULE v9: edge must pass through for exposed services and stay null for internal ones."
  }

  assert {
    condition     = output.services["svc-a"].edge.high_volume == false
    error_message = "RULE v9: high_volume is off unless the service asks for it."
  }
}

run "v9_edge_high_volume_passes_through" {
  command = plan

  variables {
    config = {
      services = [
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = { node_port = 30082, path_prefixes = ["/v1/a"], high_volume = true }
        },
      ]
    }
  }

  assert {
    condition     = output.services["svc-a"].edge.high_volume == true
    error_message = "RULE v9: edge.high_volume must reach the platform so the WAF and the gateway can apply their own limits."
  }
}

run "v9_duplicate_node_port" {
  command = plan

  variables {
    config = {
      services = [
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = { node_port = 30080, path_prefixes = ["/v1/a"] }
        },
        {
          name        = "svc-b"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = { node_port = 30080, path_prefixes = ["/v1/b"] }
        },
      ]
    }
  }

  expect_failures = [var.config]
}

run "v9_duplicate_path_prefix" {
  command = plan

  variables {
    config = {
      services = [
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = { node_port = 30080, path_prefixes = ["/v1/a"] }
        },
        {
          name        = "svc-b"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = { node_port = 30081, path_prefixes = ["/v1/a"] }
        },
      ]
    }
  }

  expect_failures = [var.config]
}

run "v9_node_port_out_of_range" {
  command = plan

  variables {
    config = {
      services = [
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = { node_port = 8080, path_prefixes = ["/v1/a"] }
        },
        {
          name        = "svc-b"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = null
        },
      ]
    }
  }

  expect_failures = [var.config]
}

run "v9_prefix_with_trailing_slash" {
  command = plan

  variables {
    config = {
      services = [
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = { node_port = 30080, path_prefixes = ["/v1/a/"] }
        },
        {
          name        = "svc-b"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          edge     = null
        },
      ]
    }
  }

  expect_failures = [var.config]
}

# HS2: topics del bus de eventos y qué servicio produce o consume cada uno.
run "events_access_and_topics_are_normalized" {
  command = plan

  variables {
    config = {
      topics = [
        { name = "solventa.a.comandos", key = "suscripcion_id" },
        { name = "solventa.b.resultados", key = "suscripcion_id", partitions = 6, dlq = false },
      ]
      services = [
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          eventos  = { produce = ["solventa.a.comandos"], consume = ["solventa.b.resultados"] }
        },
        {
          name        = "svc-b"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
        },
      ]
    }
  }

  assert {
    condition     = output.events_access["svc-a"].produce == tolist(["solventa.a.comandos"]) && output.events_access["svc-a"].consume == tolist(["solventa.b.resultados"])
    error_message = "events_access must list what each service produces and consumes."
  }

  assert {
    condition     = !contains(keys(output.events_access), "svc-b")
    error_message = "A service without events is not part of events_access."
  }

  assert {
    condition     = output.topics["solventa.a.comandos"].partitions == 3 && output.topics["solventa.a.comandos"].dlq == true && output.topics["solventa.b.resultados"].partitions == 6
    error_message = "Topics default to 3 partitions and a dead-letter topic."
  }

  assert {
    condition     = contains(output.topic_names, "solventa.a.comandos.dlq") && !contains(output.topic_names, "solventa.b.resultados.dlq")
    error_message = "topic_names includes the dead-letter topic only for topics that ask for it."
  }
}

run "a_service_cannot_use_an_undeclared_topic" {
  command = plan

  variables {
    config = {
      topics = [{ name = "solventa.a.comandos", key = "suscripcion_id" }]
      services = [
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          eventos  = { produce = ["solventa.a.comandos"], consume = ["solventa.no.declarado"] }
        },
      ]
    }
  }

  expect_failures = [var.config]
}

run "topic_names_must_be_valid_and_unique" {
  command = plan

  variables {
    config = {
      topics = [
        { name = "solventa.a.comandos", key = "x" },
        { name = "solventa.a.comandos", key = "x" },
      ]
      services = []
    }
  }

  expect_failures = [var.config]
}

run "a_topic_name_with_a_wildcard_is_rejected" {
  command = plan

  variables {
    config = {
      topics   = [{ name = "solventa.*", key = "x" }]
      services = []
    }
  }

  expect_failures = [var.config]
}

run "events_need_the_bootstrap_variable_free_for_the_platform" {
  command = plan

  variables {
    config = {
      topics = [{ name = "solventa.a.comandos", key = "x" }]
      services = [
        {
          name        = "svc-a"
          image_tag   = "x"
          port        = 80
          health_path = "/health"
          resources = {
            requests = { cpu = "1m", memory = "1Mi" }
            limits   = { cpu = "1m", memory = "1Mi" }
          }
          replicas = { min = 2, max = 2 }
          settings = { KAFKA_BOOTSTRAP_SERVERS = "algo-a-mano:9098" }
          eventos  = { produce = ["solventa.a.comandos"] }
        },
      ]
    }
  }

  expect_failures = [var.config]
}

run "v13_v14_concurrency_autoscaling_passes_through" {
  command = plan

  variables {
    config = {
      services = [{
        name        = "solventa-backend"
        image_tag   = "x"
        port        = 8000
        health_path = "/health"
        resources = {
          requests = { cpu = "1m", memory = "1Mi" }
          limits   = { cpu = "1m", memory = "1Mi" }
        }
        replicas = { min = 2, max = 10 }
        autoscaling = {
          concurrent_requests_target = 3
          scale_up                   = { pods = 4, percent = 100, period_seconds = 15, stabilization_window_seconds = 0 }
        }
        metrics_path = "/metrics"
        edge         = { node_port = 30080, path_prefixes = ["/v1/cotizaciones"] }
      }]
    }
  }

  assert {
    condition     = output.services["solventa-backend"].autoscaling.concurrent_requests_target == 3 && output.services["solventa-backend"].metrics_path == "/metrics"
    error_message = "The concurrency target and metrics_path must reach the normalized service."
  }

  assert {
    condition     = output.services["solventa-backend"].autoscaling.scale_up.percent == 100 && output.services["solventa-backend"].autoscaling.cpu_target_percent == 70
    error_message = "scale_up must pass through and cpu_target_percent keep its default."
  }
}

run "v13_metrics_path_under_an_edge_prefix_is_rejected" {
  command = plan

  variables {
    config = {
      services = [{
        name        = "solventa-backend"
        image_tag   = "x"
        port        = 8000
        health_path = "/health"
        resources = {
          requests = { cpu = "1m", memory = "1Mi" }
          limits   = { cpu = "1m", memory = "1Mi" }
        }
        replicas     = { min = 2, max = 10 }
        metrics_path = "/v1/cotizaciones/metrics"
        edge         = { node_port = 30080, path_prefixes = ["/v1/cotizaciones"] }
      }]
    }
  }

  expect_failures = [var.config]
}

run "v13_health_path_equal_to_an_edge_prefix_is_rejected" {
  command = plan

  variables {
    config = {
      services = [{
        name        = "solventa-backend"
        image_tag   = "x"
        port        = 8000
        health_path = "/health"
        resources = {
          requests = { cpu = "1m", memory = "1Mi" }
          limits   = { cpu = "1m", memory = "1Mi" }
        }
        replicas = { min = 2, max = 10 }
        edge     = { node_port = 30080, path_prefixes = ["/health"] }
      }]
    }
  }

  expect_failures = [var.config]
}

run "v14_concurrency_target_without_metrics_path_is_rejected" {
  command = plan

  variables {
    config = {
      services = [{
        name        = "solventa-backend"
        image_tag   = "x"
        port        = 8000
        health_path = "/health"
        resources = {
          requests = { cpu = "1m", memory = "1Mi" }
          limits   = { cpu = "1m", memory = "1Mi" }
        }
        replicas    = { min = 2, max = 10 }
        autoscaling = { concurrent_requests_target = 3 }
      }]
    }
  }

  expect_failures = [var.config]
}
