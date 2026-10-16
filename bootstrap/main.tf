# Raíz de bootstrap (research R3, R8): bucket de estado + identidades de pipeline.
# Vive fuera del ciclo de vida de staging: es lo único que sobrevive al teardown (SC-002).

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  state_bucket_name = coalesce(var.state_bucket_name, "solventa-tfstate-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}")

  tags = {
    Project     = "solventa"
    Environment = "bootstrap"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "bootstrap"
  }
}

module "service_list" {
  source = "../modules/service-list"

  config = yamldecode(file("${path.module}/../environments/staging/services.yaml"))
}

# ---------------------------------------------------------------------------
# Bucket de estado remoto (bloqueo nativo con use_lockfile, sin DynamoDB)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket        = local.state_bucket_name
  force_destroy = false

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = ["arn:aws:s3:::${local.state_bucket_name}", "arn:aws:s3:::${local.state_bucket_name}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# ---------------------------------------------------------------------------
# Identidades de pipeline (GitHub OIDC)
# ---------------------------------------------------------------------------
module "ci_identities" {
  source = "../modules/ci-identities"

  infra_repository            = var.infra_repository
  deploy_repositories         = { for name, s in module.service_list.services : name => s.deploy_repository }
  create_github_oidc_provider = var.create_github_oidc_provider
  state_bucket_name           = aws_s3_bucket.state.bucket
  cluster_name                = var.cluster_name
  tags                        = local.tags
}

# Ciclo de vida del bucket de estado: limita el costo de las versiones antiguas y de cargas incompletas.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}
