# Acceso de Grafana a CloudWatch (observabilidad): Grafana lee las métricas de MSK (tráfico y desfase por topic) con Pod Identity,
# sin claves en el chart. El rol es de solo lectura de métricas; no puede leer logs ni cambiar nada.

resource "aws_iam_role" "grafana" {
  name = "${var.cluster_name}-${var.service_account}-cloudwatch"

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

resource "aws_iam_role_policy" "grafana" {
  name = "grafana-cloudwatch-metricas"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LeerMetricas"
      Effect = "Allow"
      # Lo mínimo que usa la fuente de datos de CloudWatch de Grafana para listar y consultar métricas. Las acciones de
      # CloudWatch no admiten restringir por recurso: se limita a lectura.
      Action = [
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:DescribeAlarmsForMetric",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "grafana" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.grafana.arn

  tags = var.tags
}
