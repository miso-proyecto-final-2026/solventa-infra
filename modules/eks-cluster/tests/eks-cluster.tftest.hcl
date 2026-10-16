# T017: nombre, endpoint privado, CIDR públicos según la entrada, soporte estándar y accesos solo para los principales listados.

mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
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

override_data {
  target = module.eks.data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
    arn        = "arn:aws:iam::123456789012:role/mock-operator"
    user_id    = "AROAEXAMPLE"
  }
}

override_data {
  target = module.eks.data.aws_iam_session_context.current
  values = { issuer_arn = "arn:aws:iam::123456789012:role/mock-operator" }
}

override_data {
  target = module.eks.data.aws_iam_policy_document.assume_role_policy
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

override_data {
  target = module.eks.module.eks_managed_node_group["default"].data.aws_iam_policy_document.assume_role_policy
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

variables {
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0aaa", "subnet-0bbb"]

  cluster_admin_principal_arns = ["arn:aws:iam::123456789012:role/solventa-ci-infra-apply"]
  plan_role_arn                = "arn:aws:iam::123456789012:role/solventa-ci-infra-plan"
  deployer_role_arns = {
    "solventa-backend" = "arn:aws:iam::123456789012:role/solventa-ci-deploy-solventa-backend"
  }
  api_allowed_cidrs = ["203.0.113.0/24"]

  tags = {
    Project     = "solventa"
    Environment = "staging"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "platform"
  }
}

run "cluster_matches_the_contract" {
  command = plan

  assert {
    condition     = module.eks.cluster_name == "solventa-staging"
    error_message = "The cluster must be named solventa-staging."
  }

  assert {
    condition     = local.admin_entries["admin-0"].principal_arn == "arn:aws:iam::123456789012:role/solventa-ci-infra-apply"
    error_message = "RULE eks-access: admin access entries must exist only for the listed principals (FR-011)."
  }

  assert {
    condition     = length(local.admin_entries) + length(local.plan_entries) + length(local.deployer_entries) == 3
    error_message = "RULE eks-access: access entries only for admin, plan and deploy principals."
  }

  assert {
    condition     = tolist(local.deployer_entries["deploy-solventa-backend"].kubernetes_groups) == tolist(["solventa-deployers"])
    error_message = "Deploy roles must map to the solventa-deployers group."
  }

  assert {
    condition     = local.endpoint.private == true
    error_message = "RULE eks-private-endpoint: the private API endpoint must be enabled."
  }

  assert {
    condition     = tolist(local.endpoint.public_cidrs) == tolist(["203.0.113.0/24"])
    error_message = "RULE eks-api-cidrs: public endpoint CIDRs must follow api_allowed_cidrs (FR-011a)."
  }

  assert {
    condition     = local.support_type == "STANDARD"
    error_message = "RULE eks-support: support_type must be STANDARD (extended support costs 6x)."
  }

  assert {
    condition     = jsondecode(aws_iam_role.eso.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "The ESO role must be assumed through EKS Pod Identity."
  }

  assert {
    condition     = aws_eks_pod_identity_association.eso.namespace == "external-secrets" && aws_eks_pod_identity_association.eso.service_account == "external-secrets"
    error_message = "Pod Identity must target external-secrets/external-secrets."
  }
}

run "admin_principal_list_is_mandatory" {
  command = plan

  variables {
    cluster_admin_principal_arns = []
  }

  expect_failures = [var.cluster_admin_principal_arns]
}

run "invalid_public_cidr_is_rejected" {
  command = plan

  variables {
    api_allowed_cidrs = ["not-a-cidr"]
  }

  expect_failures = [var.api_allowed_cidrs]
}

override_data {
  target = module.eks.data.aws_partition.current
  values = {
    partition  = "aws"
    dns_suffix = "amazonaws.com"
  }
}

override_data {
  target = module.eks.module.eks_managed_node_group["default"].data.aws_partition.current
  values = {
    partition  = "aws"
    dns_suffix = "amazonaws.com"
  }
}
