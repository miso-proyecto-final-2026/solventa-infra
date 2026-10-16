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
    condition     = contains(keys(output.repositories), "solventa-backend")
    error_message = "One ECR repository per service in services.yaml."
  }

  assert {
    condition     = contains(keys(output.service_db_secret_names), "solventa-backend") && output.cache_secret_name == "solventa/staging/cache"
    error_message = "Secrets must be created for each service and for the cache."
  }

  assert {
    condition     = output.service_db_secret_names["solventa-backend"] == "solventa/staging/solventa-backend/db"
    error_message = "DB secret names must follow solventa/staging/<service>/db."
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
