# T011: confianza por repositorio y permisos mínimos de los roles de pipeline.

mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-1" }
}

variables {
  github_ids = {
    organization_id = "111"
    repositories = {
      "miso-proyecto-final-2026/solventa-infra"   = "222"
      "miso-proyecto-final-2026/solventa-backend" = "333"
      "miso-proyecto-final-2026/ms-prueba"        = "444"
    }
  }
  deploy_repositories = {
    "solventa-backend" = "miso-proyecto-final-2026/solventa-backend"
    "ms-prueba"        = "miso-proyecto-final-2026/ms-prueba"
  }
  state_bucket_name = "solventa-tfstate-123456789012-us-east-1"
  tags = {
    Project     = "solventa"
    Environment = "bootstrap"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "bootstrap"
  }
}

run "deploy_role_trust_is_limited_to_its_own_repository" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.service_deploy["solventa-backend"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:miso-proyecto-final-2026@111/solventa-backend@333:environment:staging"
    error_message = "RULE deploy-role-trust: the deploy role trust must be limited to its own repository and the staging environment."
  }

  assert {
    condition     = jsondecode(aws_iam_role.service_deploy["ms-prueba"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:miso-proyecto-final-2026@111/ms-prueba@444:environment:staging"
    error_message = "RULE deploy-role-trust: each service gets its own repository trust."
  }

  assert {
    condition     = aws_iam_role.service_deploy["solventa-backend"].max_session_duration == 3600
    error_message = "Roles must have a 1 h maximum session."
  }
}

run "deploy_role_permissions_limited_to_own_ecr_repo_and_cluster" {
  command = plan

  assert {
    condition = contains(
      [for s in jsondecode(aws_iam_role_policy.service_deploy["solventa-backend"].policy).Statement : s.Resource if s.Sid == "EcrPushPullOwnRepository"],
      format("arn:aws:ecr:%s:%s:repository/solventa-backend", data.aws_region.current.region, data.aws_caller_identity.current.account_id)
    )
    error_message = "RULE deploy-role-scope: ECR permissions must target only the service repository."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.service_deploy["solventa-backend"].policy, "\"*\"") || length([for s in jsondecode(aws_iam_role_policy.service_deploy["solventa-backend"].policy).Statement : s if s.Resource == "*" && s.Sid != "EcrLogin"]) == 0
    error_message = "RULE deploy-role-scope: only ecr:GetAuthorizationToken may use Resource *."
  }
}

run "plan_role_is_read_only" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.infra_plan_readonly[0].policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "RULE plan-role-readonly: the plan role must use ReadOnlyAccess."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.infra_plan.policy).Statement :
      !anytrue([for a in s.Action : startswith(a, "ec2:") || startswith(a, "rds:") || startswith(a, "eks:") || startswith(a, "iam:")])
    ])
    error_message = "RULE plan-role-readonly: the plan role must not gain write actions on platform resources."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.infra_plan.policy).Statement :
      s.Sid != "StateLockFilesOnly" || endswith(s.Resource, "*.tflock")
    ])
    error_message = "RULE plan-role-readonly: write access to state is limited to lock files."
  }

  assert {
    condition = alltrue([
      for p in jsondecode(aws_iam_role.infra_plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] :
      startswith(p, "repo:miso-proyecto-final-2026@111/solventa-infra@222:")
    ])
    error_message = "RULE plan-role-trust: the plan role must trust only the infrastructure repository."
  }
}

run "apply_role_requires_the_staging_environment" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.infra_apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:miso-proyecto-final-2026@111/solventa-infra@222:environment:staging"
    error_message = "RULE apply-role-trust: the apply role must trust only the staging environment of the infra repository."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.infra_apply.policy).Statement :
      s.Sid != "ManagePlatformIamOnly" || alltrue([for r in s.Resource : strcontains(r, "solventa-staging-")])
    ])
    error_message = "RULE apply-role-scope: IAM write actions must be limited to solventa-staging-* names."
  }
}

run "existing_oidc_provider_is_reused" {
  command = plan

  variables {
    create_github_oidc_provider = false
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "No OIDC provider must be created when create_github_oidc_provider is false."
  }
}

run "tags_are_mandatory" {
  command = plan

  variables {
    tags = { Project = "solventa" }
  }

  expect_failures = [var.tags]
}

run "subject_uses_the_immutable_ids_not_the_names" {
  command = plan

  assert {
    condition     = !strcontains(jsondecode(aws_iam_role.service_deploy["solventa-backend"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"], "miso-proyecto-final-2026/solventa-backend")
    error_message = "RULE immutable-subject: the trust must use the numeric IDs GitHub emits, not repo names."
  }
}

run "repository_without_id_fails_the_plan" {
  command = plan

  variables {
    deploy_repositories = {
      "sin-id" = "miso-proyecto-final-2026/sin-id"
    }
  }

  expect_failures = [var.github_ids]
}

run "github_ids_must_be_numeric" {
  command = plan

  variables {
    github_ids = {
      organization_id = "no-numerico"
      repositories    = {}
    }
  }

  expect_failures = [var.github_ids]
}
