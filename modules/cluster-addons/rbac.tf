# Contrato C3: permisos mínimos del pipeline de despliegue, solo en el namespace de cargas.

resource "kubernetes_role_v1" "deployers" {
  metadata {
    name      = var.deployers_group
    namespace = kubernetes_namespace_v1.staging.metadata[0].name
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "patch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["cronjobs"]
    verbs      = ["get", "list", "watch", "patch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["create", "get", "list", "watch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding_v1" "deployers" {
  metadata {
    name      = var.deployers_group
    namespace = kubernetes_namespace_v1.staging.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployers.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = var.deployers_group
  }
}
