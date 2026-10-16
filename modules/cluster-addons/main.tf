resource "kubernetes_namespace_v1" "staging" {
  metadata {
    name = var.staging_namespace

    labels = {
      "app.kubernetes.io/part-of" = "solventa"
    }
  }
}

resource "kubernetes_namespace_v1" "system" {
  metadata {
    name = var.system_namespace

    labels = {
      "app.kubernetes.io/part-of" = "solventa"
    }
  }
}

# FR-009: métricas para el HPA.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  values = [yamlencode({
    args = var.metrics_server_args
  })]

  wait = true
}

# External Secrets Operator: entrega las credenciales sin pasar por el estado de Terraform (research R9).
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = var.eso_namespace
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      name = "external-secrets"
    }
  })]

  wait = true
}
