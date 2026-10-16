# ClusterSecretStore único para todas las cargas. En AWS lee Secrets Manager con Pod Identity;
# en kind lee Secrets del namespace local-secrets (mismo módulo baseline, otra entrada).

locals {
  aws_store_spec = {
    provider = {
      aws = {
        service = "SecretsManager"
        region  = var.secret_store.region
      }
    }
  }

  kubernetes_store_spec = {
    provider = {
      kubernetes = {
        remoteNamespace = var.secret_store.namespace
        server = {
          caProvider = {
            type      = "ConfigMap"
            name      = "kube-root-ca.crt"
            key       = "ca.crt"
            namespace = var.eso_namespace
          }
        }
        auth = {
          serviceAccount = {
            name      = "external-secrets"
            namespace = var.eso_namespace
          }
        }
      }
    }
  }

  store_spec = jsondecode(var.secret_store.kind == "aws" ? jsonencode(local.aws_store_spec) : jsonencode(local.kubernetes_store_spec))
}

resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata   = { name = var.secret_store.name }
    spec       = local.store_spec
  })

  depends_on = [helm_release.external_secrets]
}

# Solo kind: permisos para que ESO lea los Secrets de origen del namespace local-secrets.
resource "kubernetes_role_v1" "eso_local_source" {
  count = var.secret_store.kind == "kubernetes" ? 1 : 0

  metadata {
    name      = "eso-read-local-secrets"
    namespace = var.secret_store.namespace
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["authorization.k8s.io"]
    resources  = ["selfsubjectrulesreviews"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding_v1" "eso_local_source" {
  count = var.secret_store.kind == "kubernetes" ? 1 : 0

  metadata {
    name      = "eso-read-local-secrets"
    namespace = var.secret_store.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.eso_local_source[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "external-secrets"
    namespace = var.eso_namespace
  }

  depends_on = [helm_release.external_secrets]
}

# Solo kind: ESO pide tokens de su propia ServiceAccount para autenticarse contra la API local.
resource "kubernetes_role_v1" "eso_token_self" {
  count = var.secret_store.kind == "kubernetes" ? 1 : 0

  metadata {
    name      = "eso-create-own-token"
    namespace = var.eso_namespace
  }

  rule {
    api_groups     = [""]
    resources      = ["serviceaccounts/token"]
    resource_names = ["external-secrets"]
    verbs          = ["create"]
  }

  depends_on = [helm_release.external_secrets]
}

resource "kubernetes_role_binding_v1" "eso_token_self" {
  count = var.secret_store.kind == "kubernetes" ? 1 : 0

  metadata {
    name      = "eso-create-own-token"
    namespace = var.eso_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.eso_token_self[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "external-secrets"
    namespace = var.eso_namespace
  }
}
