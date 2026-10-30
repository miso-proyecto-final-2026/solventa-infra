# Bucket de evidencias de identidad (HU02, criterio 7): cifrado, sin acceso público, solo TLS y con
# escritura limitada al servicio que las genera. La lectura queda fuera: la revisión manual de un caso
# EN_REVISION usará otro rol con su propia política.
#
# También sirve para los documentos de póliza (HU20) con `existing_role_name`: el permiso de escritura se
# adjunta al rol que el servicio ya asume (EKS admite una sola asociación de Pod Identity por cuenta de
# servicio) y la retención puede ser indefinida (`retention_days = null`).
#
# Las pólizas firmadas (HU21) suman un segundo prefijo de escritura (`extra_write_prefixes`) y permiso de lectura
# (`read_access`) sobre los mismos prefijos: el servicio relee el PDF para comprobar su hash y devolver la copia firmada.

locals {
  # Derivado del nombre (conocido en el plan) para que las políticas se puedan comprobar sin aplicar.
  bucket_arn = "arn:aws:s3:::${var.bucket_name}"

  # Con `existing_role_name` no se crea rol ni asociación: la política se adjunta al rol dado.
  create_role      = var.existing_role_name == null
  writer_role_name = local.create_role ? aws_iam_role.writer[0].name : var.existing_role_name

  # Solo los prefijos declarados: ni el bucket completo ni otros servicios. La lectura (si se pide) cubre los mismos.
  object_arns = [for p in concat([var.prefix], var.extra_write_prefixes) : "${local.bucket_arn}/${p}*"]
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced" # sin ACL: solo políticas
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "retencion-de-evidencias"
    status = "Enabled"

    filter {}

    # Sin `retention_days` los objetos actuales no expiran (documentos de póliza); las versiones antiguas sí.
    dynamic "expiration" {
      for_each = var.retention_days == null ? [] : [var.retention_days]

      content {
        days = expiration.value
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---------------------------------------------------------------------------
# Acceso del servicio: Pod Identity, PutObject bajo los prefijos de evidencias (y GetObject si `read_access`)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "writer" {
  count = local.create_role ? 1 : 0

  name = "${var.cluster_name}-${var.service_account}-evidencias"

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

resource "aws_iam_role_policy" "writer" {
  name = var.policy_name
  role = local.writer_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${local.bucket_arn}/${var.prefix}*"
      }],
      length(var.extra_write_prefixes) == 0 ? [] : [{
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = [for p in var.extra_write_prefixes : "${local.bucket_arn}/${p}*"]
      }],
      var.read_access ? [{
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = local.object_arns
      }] : [],
    )
  })
}

resource "aws_eks_pod_identity_association" "writer" {
  count = local.create_role ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.writer[0].arn

  tags = var.tags
}

# El rol y la asociación pasaron a tener `count`: se mueven en el estado para no recrearlos (el bucket de KYC ya existe).
moved {
  from = aws_iam_role.writer
  to   = aws_iam_role.writer[0]
}

moved {
  from = aws_eks_pod_identity_association.writer
  to   = aws_eks_pod_identity_association.writer[0]
}
