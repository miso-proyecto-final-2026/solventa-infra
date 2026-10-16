# Pod Identity de External Secrets Operator: lectura de secretos solventa/staging/* y del secreto maestro de RDS.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  secrets_arn_pattern = "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${var.secrets_prefix}/*"
  readable_secrets    = compact([local.secrets_arn_pattern, var.db_admin_secret_arn])
}

resource "aws_iam_role" "eso" {
  name = "${var.cluster_name}-eso"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "eso" {
  name = "read-solventa-secrets"
  role = aws_iam_role.eso.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = local.readable_secrets
    }]
  })
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = module.eks.cluster_name
  namespace       = var.eso_namespace
  service_account = var.eso_service_account
  role_arn        = aws_iam_role.eso.arn

  tags = var.tags
}
