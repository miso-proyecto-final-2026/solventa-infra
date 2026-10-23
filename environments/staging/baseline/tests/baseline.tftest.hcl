# T036: con proveedores simulados, el plan produce el conjunto E7 de solventa-backend y falla si la imagen no existe.

mock_provider "aws" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "kubectl" {}

override_data {
  target = data.terraform_remote_state.platform
  values = {
    outputs = {
      region                 = "us-east-1"
      cluster_name           = "solventa-staging"
      cluster_endpoint       = "https://ABCDEF.gr7.us-east-1.eks.amazonaws.com"
      cluster_ca_data        = "ZmFrZS1jYQ=="
      registry_url           = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
      db_endpoint            = "solventa-staging-postgres.abc.us-east-1.rds.amazonaws.com"
      db_port                = 5432
      db_name                = "solventa"
      db_admin_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-abc"
      cache_primary_endpoint = "solventa-staging-cache.abc.cache.amazonaws.com"
      cache_secret_name      = "solventa/staging/cache"
      kyc_evidencias_bucket  = "solventa-staging-kyc-evidencias-123456789012"
      service_db_secret_names = {
        "solventa-backend"       = "solventa/staging/solventa-backend/db"
        "solventa-identidad"     = "solventa/staging/solventa-identidad/db"
        "solventa-perfilamiento" = "solventa/staging/solventa-perfilamiento/db"
        "solventa-siniestros"    = "solventa/staging/solventa-siniestros/db"
      }
      service_db_secret_versions = {
        "solventa-backend"       = "11111111-2222-3333-4444-555555555555"
        "solventa-identidad"     = "66666666-7777-8888-9999-000000000000"
        "solventa-perfilamiento" = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        "solventa-siniestros"    = "bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
      }
    }
  }
}

variables {
  state_bucket = "solventa-tfstate-123456789012-us-east-1"
  image_tags = {
    "solventa-backend"       = "abc1234"
    "solventa-identidad"     = "abc1234"
    "solventa-perfilamiento" = "abc1234"
    "solventa-siniestros"    = "abc1234"
  }
}

run "plan_produces_the_full_workload_set" {
  command = plan

  override_data {
    target = data.aws_ecr_images.service["solventa-backend"]
    values = {
      image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }]
    }
  }

  override_data {
    target = data.aws_ecr_images.service["solventa-identidad"]
    values = {
      image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }]
    }
  }

  override_data {
    target = data.aws_ecr_images.service["solventa-perfilamiento"]
    values = {
      image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }]
    }
  }

  override_data {
    target = data.aws_ecr_images.service["solventa-siniestros"]
    values = {
      image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }]
    }
  }

  assert {
    condition     = output.deployments["solventa-identidad"] == "solventa-identidad" && startswith(output.migration_jobs["solventa-identidad"], "solventa-identidad-migrate-")
    error_message = "The baseline must create the solventa-identidad Deployment and its migration Job."
  }

  assert {
    condition     = output.deployments["solventa-backend"] == "solventa-backend"
    error_message = "The baseline must create the solventa-backend Deployment."
  }

  assert {
    condition     = startswith(output.migration_jobs["solventa-backend"], "solventa-backend-migrate-")
    error_message = "The baseline must create the migration Job before the Deployment."
  }

  assert {
    condition     = output.deployments["solventa-perfilamiento"] == "solventa-perfilamiento" && startswith(output.migration_jobs["solventa-perfilamiento"], "solventa-perfilamiento-migrate-")
    error_message = "The baseline must create the solventa-perfilamiento Deployment and its migration Job."
  }

  # HU27: Siniestros tiene su Deployment y su migración, y sí se publica por el borde (el proveedor de eventos es externo).
  assert {
    condition     = output.deployments["solventa-siniestros"] == "solventa-siniestros" && startswith(output.migration_jobs["solventa-siniestros"], "solventa-siniestros-migrate-")
    error_message = "The baseline must create the solventa-siniestros Deployment and its migration Job."
  }

  assert {
    condition     = output.edge_node_ports["solventa-siniestros"] == 30082
    error_message = "RULE edge-nodeport: solventa-siniestros must get its edge NodePort (30082)."
  }

  # Perfilamiento es interno: sin `edge` no se publica por el borde.
  assert {
    condition     = !contains(keys(output.edge_node_ports), "solventa-perfilamiento")
    error_message = "RULE internal-only: solventa-perfilamiento must not get an edge NodePort."
  }

  assert {
    condition     = startswith(output.db_access_job, "db-access-")
    error_message = "The baseline must run the db-access Job."
  }

  # El tipo de `services` del módulo baseline descarta en silencio los atributos que no declara:
  # sin `edge` en él, el borde público recibiría 503 porque no existiría ningún NodePort.
  assert {
    condition     = output.edge_node_ports["solventa-backend"] == 30080 && output.edge_node_ports["solventa-identidad"] == 30081
    error_message = "RULE edge-nodeport: the baseline must create the NodePort Services declared under edge in services.yaml."
  }
}

run "missing_image_fails_before_any_workload" {
  command = plan

  override_data {
    target = data.aws_ecr_images.service["solventa-backend"]
    values = {
      image_ids = [{ image_tag = "other", image_digest = "sha256:1111" }]
    }
  }

  override_data {
    target = data.aws_ecr_images.service["solventa-identidad"]
    values = {
      image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }]
    }
  }

  override_data {
    target = data.aws_ecr_images.service["solventa-perfilamiento"]
    values = {
      image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }]
    }
  }

  override_data {
    target = data.aws_ecr_images.service["solventa-siniestros"]
    values = {
      image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }]
    }
  }

  expect_failures = [terraform_data.image_check["solventa-backend"]]
}

run "image_check_can_be_disabled" {
  command = plan

  variables {
    check_images_exist = false
  }

  assert {
    condition     = length(terraform_data.image_check) == 0
    error_message = "check_images_exist = false must skip the ECR lookup."
  }
}

# HS2: con el bus de eventos en la plataforma, el baseline crea los topics y entrega los brokers a quien los usa.
run "events_create_topics_and_inject_the_brokers" {
  command = plan

  override_data {
    target = data.terraform_remote_state.platform
    values = {
      outputs = {
        region                  = "us-east-1"
        cluster_name            = "solventa-staging"
        cluster_endpoint        = "https://ABCDEF.gr7.us-east-1.eks.amazonaws.com"
        cluster_ca_data         = "ZmFrZS1jYQ=="
        registry_url            = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
        db_endpoint             = "solventa-staging-postgres.abc.us-east-1.rds.amazonaws.com"
        db_port                 = 5432
        db_name                 = "solventa"
        db_admin_secret_arn     = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-abc"
        cache_primary_endpoint  = "solventa-staging-cache.abc.cache.amazonaws.com"
        cache_secret_name       = "solventa/staging/cache"
        kyc_evidencias_bucket   = "solventa-staging-kyc-evidencias-123456789012"
        kafka_bootstrap_brokers = "b-1.eventos.abc.kafka.us-east-1.amazonaws.com:9098,b-2.eventos.abc.kafka.us-east-1.amazonaws.com:9098"
        service_db_secret_names = {
          "solventa-backend"       = "solventa/staging/solventa-backend/db"
          "solventa-identidad"     = "solventa/staging/solventa-identidad/db"
          "solventa-perfilamiento" = "solventa/staging/solventa-perfilamiento/db"
          "solventa-siniestros"    = "solventa/staging/solventa-siniestros/db"
        }
        service_db_secret_versions = {
          "solventa-backend"       = "11111111-2222-3333-4444-555555555555"
          "solventa-identidad"     = "66666666-7777-8888-9999-000000000000"
          "solventa-perfilamiento" = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
          "solventa-siniestros"    = "bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
        }
      }
    }
  }

  override_data {
    target = data.aws_ecr_images.service["solventa-backend"]
    values = { image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }] }
  }

  override_data {
    target = data.aws_ecr_images.service["solventa-identidad"]
    values = { image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }] }
  }

  override_data {
    target = data.aws_ecr_images.service["solventa-perfilamiento"]
    values = { image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }] }
  }

  override_data {
    target = data.aws_ecr_images.service["solventa-siniestros"]
    values = { image_ids = [{ image_tag = "abc1234", image_digest = "sha256:0000" }] }
  }

  assert {
    condition     = module.baseline.kafka_topics_job != null
    error_message = "HS2: with kafka_bootstrap_brokers in the platform, the topics Job exists."
  }

  assert {
    condition     = contains(keys(module.service_list.events_access), "solventa-siniestros")
    error_message = "HU27: solventa-siniestros declares eventos in services.yaml and must get bus access."
  }

  assert {
    condition     = local.services["solventa-siniestros"].settings["AWS_DEFAULT_REGION"] == "us-east-1" && can(regex("9098", local.services["solventa-siniestros"].settings["KAFKA_BOOTSTRAP_SERVERS"]))
    error_message = "HU27: a service with eventos receives the brokers and the region (the client signs the SASL/IAM token with it)."
  }

  assert {
    condition     = contains(keys(module.service_list.topics), "solventa.suscripcion.comandos")
    error_message = "HS2: the topics come from services.yaml."
  }
}
