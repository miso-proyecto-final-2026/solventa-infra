# T022: reglas FR-030 a nivel de composición y contrato C4 (sin credenciales en las salidas).
# Se usan proveedores simulados: no hay llamadas a AWS.

mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      address = "solventa-staging-postgres.abc.us-east-1.rds.amazonaws.com"
      port    = 5432
    }
  }

  mock_resource "aws_elasticache_replication_group" {
    defaults = {
      primary_endpoint_address = "solventa-staging-cache.abc.cache.amazonaws.com"
      port                     = 6379
    }
  }
}

mock_provider "random" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

override_data {
  target = module.network.data.aws_availability_zones.available
  values = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
}

override_data {
  target = module.network.data.aws_region.current
  values = { region = "us-east-1" }
}

override_data {
  target = module.cloudfront[0].data.aws_region.current
  values = { region = "us-east-1" }
}

override_data {
  target = module.eks.data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

override_data {
  target = module.eks.data.aws_region.current
  values = { region = "us-east-1" }
}

override_data {
  target = module.eks.module.eks.data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
    arn        = "arn:aws:iam::123456789012:role/mock-operator"
    user_id    = "AROAEXAMPLE"
  }
}

override_data {
  target = module.eks.module.eks.data.aws_iam_session_context.current
  values = { issuer_arn = "arn:aws:iam::123456789012:role/mock-operator" }
}

override_data {
  target = module.eks.module.eks.data.aws_partition.current
  values = {
    partition  = "aws"
    dns_suffix = "amazonaws.com"
  }
}

override_data {
  target = module.eks.module.eks.data.aws_iam_policy_document.assume_role_policy
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

override_data {
  target = module.eks.module.eks.module.eks_managed_node_group["default"].data.aws_iam_policy_document.assume_role_policy
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

override_data {
  target = module.eks.module.eks.module.eks_managed_node_group["default"].data.aws_partition.current
  values = {
    partition  = "aws"
    dns_suffix = "amazonaws.com"
  }
}

override_resource {
  target          = module.redis.random_password.auth_token
  override_during = plan
  values          = { result = "AbCdEfGhIjKlMnOpQrStUvWxYz012345" }
}

run "platform_composition_follows_the_contract" {
  command = plan

  variables {
    cluster_admin_principal_arns = ["arn:aws:iam::123456789012:user/operador"]
  }

  assert {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(local.tags), k)])
    error_message = "RULE tags: the platform must define the five mandatory tags (FR-005)."
  }

  assert {
    condition     = local.tags["Stage"] == "platform" && local.tags["Environment"] == "staging"
    error_message = "Tags must identify the platform stage of staging."
  }

  assert {
    condition     = length(module.eks.cluster_name) > 0 && output.cluster_name == "solventa-staging"
    error_message = "The cluster must be named solventa-staging."
  }

  assert {
    condition     = contains(keys(output.repositories), "solventa-backend") && contains(keys(output.repositories), "solventa-identidad")
    error_message = "One ECR repository per service in services.yaml."
  }

  assert {
    condition     = contains(keys(output.service_db_secret_names), "solventa-backend") && output.cache_secret_name == "solventa/staging/cache"
    error_message = "Secrets must be created for each service and for the cache."
  }

  assert {
    condition     = output.service_db_secret_names["solventa-backend"] == "solventa/staging/solventa-backend/db" && output.service_db_secret_names["solventa-identidad"] == "solventa/staging/solventa-identidad/db"
    error_message = "DB secret names must follow solventa/staging/<service>/db."
  }

  assert {
    condition     = output.kyc_evidencias_bucket == "solventa-staging-kyc-evidencias-123456789012"
    error_message = "The KYC evidence bucket must be named solventa-<env>-kyc-evidencias-<account>."
  }

  assert {
    condition     = output.registry_url == "123456789012.dkr.ecr.us-east-1.amazonaws.com"
    error_message = "registry_url must be the account ECR registry."
  }
}

run "outputs_expose_no_credentials" {
  command = plan

  assert {
    condition = !can(regex("(?i)password|secret_string|authtoken|postgresql[+]psycopg|rediss?://", jsonencode({
      names    = output.service_db_secret_names
      cache    = output.cache_secret_name
      repos    = keys(output.repositories)
      region   = output.region
      registry = output.registry_url
      cluster  = output.cluster_name
    })))
    error_message = "RULE outputs: secret references must not contain credential values."
  }
}

run "minimum_node_count_is_enforced" {
  command = plan

  variables {
    node_count = 1
  }

  expect_failures = [var.node_count]
}

run "edge_follows_the_architecture_path" {
  command = plan

  assert {
    condition     = length(module.nlb) == 1 && length(module.api_gateway) == 1 && length(module.cloudfront) == 1
    error_message = "RULE edge: CloudFront + WAF, API Gateway and the NLB must be created when services declare edge."
  }

  assert {
    condition     = length(module.nlb[0].listener_arns) == 3
    error_message = "RULE edge-services: solventa-backend, solventa-identidad and solventa-suscripcion must be exposed through the NLB."
  }

  assert {
    condition     = alltrue([for k in ["solventa-backend", "solventa-identidad", "solventa-suscripcion"] : contains(keys(module.nlb[0].listener_arns), k)])
    error_message = "RULE edge-wiring: each exposed service must have its own NLB listener."
  }
}

run "edge_can_be_disabled" {
  command = plan

  variables {
    enable_edge = false
  }

  assert {
    condition     = length(module.nlb) == 0 && length(module.api_gateway) == 0 && length(module.cloudfront) == 0
    error_message = "RULE edge-off: with enable_edge=false no edge resource is created."
  }

  assert {
    condition     = output.public_url == null
    error_message = "RULE edge-off: public_url must be null when the edge is disabled."
  }
}

run "event_bus_is_part_of_the_platform_and_can_be_switched_off" {
  command = plan

  variables {
    cluster_admin_principal_arns = ["arn:aws:iam::123456789012:user/operador"]
  }

  assert {
    condition     = length(module.msk) == 1
    error_message = "HS2: the event bus is created by default."
  }

  assert {
    condition     = contains(keys(module.service_list.topics), "solventa.suscripcion.comandos") && contains(keys(module.service_list.topics), "solventa.pagos.resultados")
    error_message = "HS2: the contract topics of section 4.2 are declared in services.yaml."
  }

  assert {
    condition     = contains(module.service_list.topic_names, "solventa.identidad.consentimiento.dlq") && !contains(module.service_list.topic_names, "solventa.humo.dlq")
    error_message = "HS2: every topic has a dead-letter topic except the smoke-test one."
  }

  assert {
    condition     = contains(keys(module.msk[0].client_role_arns), "kafka-humo")
    error_message = "HS2: the smoke test has its own minimal identity."
  }
}

run "event_bus_off_creates_nothing" {
  command = plan

  variables {
    cluster_admin_principal_arns = ["arn:aws:iam::123456789012:user/operador"]
    enable_events                = false
  }

  assert {
    condition     = length(module.msk) == 0 && output.kafka_bootstrap_brokers == null
    error_message = "HS2: with enable_events = false there is no cluster and no broker output."
  }
}
