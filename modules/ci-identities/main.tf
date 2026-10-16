data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = "aws"
  region     = data.aws_region.current.region
  oidc_host  = "token.actions.githubusercontent.com"

  # El ARN del proveedor solo depende de la URL: se calcula para que las políticas sean conocidas en el plan.
  oidc_provider_arn = "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.oidc_host}"

  state_bucket_arn = "arn:${local.partition}:s3:::${var.state_bucket_name}"

  # Los recursos de la plataforma usan nombres deterministas (research R8).
  platform_iam_prefix = "solventa-staging-"
  cluster_arn         = "arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.cluster_name}"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Rol de plan: solo lectura (PRs y main del repositorio de infraestructura)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "infra_plan" {
  name                 = "solventa-ci-infra-plan"
  max_session_duration = var.max_session_duration
  depends_on           = [aws_iam_openid_connect_provider.github]

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = [
            "repo:${var.infra_repository}:pull_request",
            "repo:${var.infra_repository}:ref:refs/heads/main",
          ]
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "infra_plan_readonly" {
  role       = aws_iam_role.infra_plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "infra_plan" {
  name = "state-and-secrets-read"
  role = aws_iam_role.infra_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
      },
      {
        Sid      = "StateLockFilesOnly"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.state_bucket_arn}/*.tflock"
      },
      {
        Sid      = "RefreshSecretVersions"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:solventa/staging/*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Rol de apply: solo desde el GitHub environment `staging` (revisores requeridos)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "infra_apply" {
  name                 = "solventa-ci-infra-apply"
  max_session_duration = var.max_session_duration
  depends_on           = [aws_iam_openid_connect_provider.github]

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "repo:${var.infra_repository}:environment:${var.environment_name}"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "infra_apply_poweruser" {
  role       = aws_iam_role.infra_apply.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "infra_apply" {
  name = "scoped-iam-and-state"
  role = aws_iam_role.infra_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManagePlatformIamOnly"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
          "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags", "iam:PutRolePolicy", "iam:GetRolePolicy",
          "iam:DeleteRolePolicy", "iam:ListRolePolicies", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:CreatePolicy",
          "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:TagPolicy", "iam:UntagPolicy",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
        ]
        Resource = [
          "arn:${local.partition}:iam::${local.account_id}:role/${local.platform_iam_prefix}*",
          "arn:${local.partition}:iam::${local.account_id}:policy/${local.platform_iam_prefix}*",
          "arn:${local.partition}:iam::${local.account_id}:instance-profile/${local.platform_iam_prefix}*",
        ]
      },
      {
        Sid      = "PassPlatformRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:${local.partition}:iam::${local.account_id}:role/${local.platform_iam_prefix}*"
      },
      {
        Sid      = "ServiceLinkedRoles"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"
      },
      {
        Sid      = "ReadIamForRefresh"
        Effect   = "Allow"
        Action   = ["iam:Get*", "iam:List*"]
        Resource = "*"
      },
      {
        Sid      = "StateReadWrite"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Un rol de despliegue por servicio: confianza limitada a su propio repositorio
# ---------------------------------------------------------------------------
resource "aws_iam_role" "service_deploy" {
  for_each = var.deploy_repositories

  name                 = "solventa-ci-deploy-${each.key}"
  max_session_duration = var.max_session_duration
  depends_on           = [aws_iam_openid_connect_provider.github]

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "repo:${each.value}:environment:${var.environment_name}"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "service_deploy" {
  for_each = var.deploy_repositories

  name = "ecr-push-and-cluster-describe"
  role = aws_iam_role.service_deploy[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPushPullOwnRepository"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
          "ecr:DescribeImages",
        ]
        Resource = "arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/${each.key}"
      },
      {
        Sid      = "DescribeCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = local.cluster_arn
      },
    ]
  })
}
