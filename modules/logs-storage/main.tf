# Almacenamiento de logs de Loki en S3 (observabilidad): los logs sobreviven a los reinicios del pod y se pueden
# conservar más tiempo que en el disco del nodo. Cifrado, sin acceso público y solo TLS.
#
# Loki accede con Pod Identity (sin claves en el chart): el rol solo toca este bucket. La retención la aplica
# Loki (compactor); la regla de ciclo de vida del bucket es la red de seguridad si el compactor falla.

locals {
  # Derivado del nombre (conocido en el plan) para que las políticas se puedan comprobar sin aplicar.
  bucket_arn = "arn:aws:s3:::${var.bucket_name}"
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

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Sin versionado: Loki escribe chunks inmutables y borra los vencidos; guardar versiones solo sumaría costo.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "red-de-seguridad-de-retencion"
    status = "Enabled"

    filter {}

    expiration {
      days = var.retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
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
# Acceso de Loki: Pod Identity, solo este bucket
# ---------------------------------------------------------------------------
resource "aws_iam_role" "loki" {
  name = "${var.cluster_name}-${var.service_account}-logs"

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

resource "aws_iam_role_policy" "loki" {
  name = "loki-logs-bucket"
  role = aws_iam_role.loki.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListarBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = local.bucket_arn
      },
      {
        Sid      = "LeerEscribirYBorrarObjetos" # Borrar: lo necesita el compactor para aplicar la retención.
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.bucket_arn}/*"
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "loki" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.loki.arn

  tags = var.tags
}
